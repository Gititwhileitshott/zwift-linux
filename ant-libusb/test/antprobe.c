/*
 * antprobe.exe - 64-bit Windows test for the libusb0.dll shim under Wine.
 * Loads libusb0.dll exactly the way a Windows app (e.g. ZwiftApp.exe) would,
 * checks the calling convention, lists USB devices and, if an ANT USB stick
 * (0fcf:1008 / 0fcf:1009) is present, sends an ANT "Reset System" and
 * "Request Capabilities" message and prints the replies.
 * Build: x86_64-w64-mingw32-gcc -O2 -o antprobe.exe antprobe.c
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

#pragma pack(push, 1)
struct usb_device_descriptor { unsigned char bLength, bDescriptorType; unsigned short bcdUSB;
  unsigned char bDeviceClass, bDeviceSubClass, bDeviceProtocol, bMaxPacketSize0;
  unsigned short idVendor, idProduct, bcdDevice; unsigned char iManufacturer, iProduct, iSerialNumber, bNumConfigurations; };
struct usb_bus;
struct usb_device { struct usb_device *next, *prev; char filename[512]; struct usb_bus *bus;
  struct usb_device_descriptor descriptor; void *config; void *dev; unsigned char devnum;
  unsigned char num_children; struct usb_device **children; };
struct usb_bus { struct usb_bus *next, *prev; char dirname[512]; struct usb_device *devices;
  unsigned int location; struct usb_device *root_dev; };
#pragma pack(pop)

typedef void  (__cdecl *f_init)(void);
typedef int   (__cdecl *f_int0)(void);
typedef struct usb_bus *(__cdecl *f_busses)(void);
typedef void *(__cdecl *f_open)(struct usb_device *);
typedef struct usb_device *(__cdecl *f_device)(void *);
typedef int   (__cdecl *f_close)(void *);
typedef int   (__cdecl *f_int1)(void *, int);
typedef int   (__cdecl *f_bulk)(void *, int, char *, int, int);
typedef const char *(__cdecl *f_err)(void);
typedef int   (__cdecl *f_setup)(void *, void **, unsigned char);
typedef int   (__cdecl *f_submit)(void *, char *, int);
typedef int   (__cdecl *f_reap)(void *, int);
typedef int   (__cdecl *f_free)(void **);

/* async receive thread, the way Dynastream's ANT_DLL reads the stick */
static f_submit p_submit; static f_reap p_reap_nc;
static void *rx_ctx; static volatile LONG rx_stop, got_caps, got_assign, got_unassign, rx_msgs;
static DWORD WINAPI rx_thread(LPVOID unused)
{
  unsigned char buf[64]; int r, i, pending = 0;
  (void)unused;
  while (!rx_stop) {
    if (!pending) { if (p_submit(rx_ctx, (char *)buf, sizeof buf) < 0) { printf("FAIL: usb_submit_async\n"); return 1; } pending = 1; }
    r = p_reap_nc(rx_ctx, 100);
    if (r == -116) continue;            /* timeout, request still pending: exactly what ANT_DLL expects */
    pending = 0;
    if (r <= 0) { printf("  async reap error %d\n", r); Sleep(10); continue; }
    InterlockedIncrement(&rx_msgs);
    printf("  async rx:"); for (i = 0; i < r; i++) printf(" %02X", buf[i]); printf("\n");
    for (i = 0; i + 5 < r; i++) if (buf[i] == 0xA4) {
      if (buf[i + 2] == 0x54) got_caps = 1;
      if (buf[i + 2] == 0x40 && buf[i + 4] == 0x42) got_assign = buf[i + 5] == 0 ? 1 : -1;
      if (buf[i + 2] == 0x40 && buf[i + 4] == 0x41) got_unassign = buf[i + 5] == 0 ? 1 : -1;
    }
  }
  return 0;
}
static int wait_flag(volatile LONG *f, int ms) { while (!*f && ms > 0) { Sleep(20); ms -= 20; } return *f; }

#define LOAD(t, n) t n = (t)GetProcAddress(h, #n); if (!n) { printf("FAIL: export %s missing\n", #n); return 2; }

static int ant_msg(unsigned char *out, unsigned char id, const unsigned char *data, int len)
{
  int i; unsigned char cs;
  out[0] = 0xA4; out[1] = (unsigned char)len; out[2] = id;
  memcpy(out + 3, data, len);
  cs = 0; for (i = 0; i < 3 + len; i++) cs ^= out[i];
  out[3 + len] = cs;
  return 4 + len;
}

int main(void)
{
  HMODULE h = LoadLibraryA("libusb0.dll");
  struct usb_device fake; struct usb_bus fakebus; struct usb_bus *b; struct usb_device *d, *ant = NULL;
  void *hd; int n = 0, r;
  if (!h) { printf("FAIL: LoadLibrary(libusb0.dll) error %lu\n", GetLastError()); return 1; }
  {
    char path[MAX_PATH] = ""; GetModuleFileNameA(h, path, sizeof path);
    if (GetProcAddress(h, "libusb0_wine_bridge_version"))
      printf("OK: libusb0.dll loaded (Wine bridge -> Linux USB) from %s\n", path);
    else
      printf("WARN: libusb0.dll loaded from %s is the WINDOWS libusb-win32 DLL, not the Wine bridge.\n"
             "      It needs the libusb0.sys kernel driver, which cannot run under Wine, so no devices will be found.\n"
             "      Fix: WINEDLLOVERRIDES=libusb0=b and install the bridge into Wine's lib dir.\n", path);
  }
  LOAD(f_init, usb_init) LOAD(f_int0, usb_find_busses) LOAD(f_int0, usb_find_devices)
  LOAD(f_busses, usb_get_busses) LOAD(f_open, usb_open) LOAD(f_device, usb_device)
  LOAD(f_close, usb_close) LOAD(f_int1, usb_set_configuration) LOAD(f_int1, usb_claim_interface)
  LOAD(f_int1, usb_release_interface) LOAD(f_bulk, usb_bulk_write) LOAD(f_bulk, usb_bulk_read)
  LOAD(f_err, usb_strerror)
  LOAD(f_setup, usb_bulk_setup_async) LOAD(f_submit, usb_submit_async) LOAD(f_reap, usb_reap_async_nocancel)
  LOAD(f_free, usb_free_async) LOAD(f_bulk, usb_interrupt_write)
  p_submit = usb_submit_async; p_reap_nc = usb_reap_async_nocancel;

  /* 1. calling-convention check: usb_open() must receive the pointer we pass */
  memset(&fake, 0, sizeof fake); memset(&fakebus, 0, sizeof fakebus);
  strcpy(fakebus.dirname, "999"); strcpy(fake.filename, "999"); fake.bus = &fakebus;
  hd = usb_open(&fake);
  if (!hd || usb_device(hd) != &fake) { printf("FAIL: ABI mismatch - usb_open did not receive our argument\n"); return 3; }
  usb_close(hd);
  printf("OK: Windows x64 calling convention verified\n");

  /* 2. enumerate */
  usb_init(); usb_find_busses(); usb_find_devices();
  for (b = usb_get_busses(); b; b = b->next)
    for (d = b->devices; d; d = d->next) {
      n++;
      printf("  bus %s dev %s  %04x:%04x\n", b->dirname, d->filename, d->descriptor.idVendor, d->descriptor.idProduct);
      if (d->descriptor.idVendor == 0x0fcf && (d->descriptor.idProduct == 0x1008 || d->descriptor.idProduct == 0x1009)) ant = d;
    }
  printf("OK: %d USB device(s) enumerated\n", n);
  if (!ant) { printf("INFO: no ANT USB stick (0fcf:1008/1009) found - plug one in and check udev permissions\n"); return 0; }

  /* 3. talk to the ANT stick */
  {
    unsigned char msg[16], buf[64]; int len, i, tries;
    unsigned char rst[1] = {0}, req[2] = {0, 0x54};
    hd = usb_open(ant);
    if (!hd) { printf("FAIL: usb_open(ANT): %s\n", usb_strerror()); return 4; }
    usb_set_configuration(hd, 1);
    if ((r = usb_claim_interface(hd, 0)) < 0) { printf("FAIL: claim_interface: %s (udev permissions?)\n", usb_strerror()); return 5; }
    len = ant_msg(msg, 0x4A, rst, 1);
    r = usb_bulk_write(hd, 0x01, (char *)msg, len, 1000);
    printf("%s: ANT reset sent (%d)\n", r == len ? "OK" : "FAIL", r);
    Sleep(600);
    len = ant_msg(msg, 0x4D, req, 2);
    usb_bulk_write(hd, 0x01, (char *)msg, len, 1000);
    for (tries = 0; tries < 4; tries++) {
      r = usb_bulk_read(hd, 0x81, (char *)buf, sizeof buf, 1000);
      if (r <= 0) continue;
      printf("  rx:"); for (i = 0; i < r; i++) printf(" %02X", buf[i]); printf("\n");
      for (i = 0; i + 2 < r; i++)
        if (buf[i] == 0xA4 && buf[i + 2] == 0x54) {
          printf("OK: ANT capabilities reply received (synchronous read)\n");
          goto async_test;
        }
    }
    printf("FAIL: no capabilities reply from ANT stick\n");
    usb_release_interface(hd, 0); usb_close(hd); return 6;

async_test:
    /* 4. Zwift's pattern: async reader thread + usb_interrupt_write commands */
    {
      unsigned char assign[3] = {0x00, 0x00, 0x00}, unassign[1] = {0x00};
      HANDLE th; int ok = 1;
      if (usb_bulk_setup_async(hd, &rx_ctx, 0x81) < 0) { printf("FAIL: usb_bulk_setup_async\n"); return 7; }
      th = CreateThread(NULL, 0, rx_thread, NULL, 0, NULL);
      Sleep(300);
      len = ant_msg(msg, 0x4D, req, 2);
      r = usb_interrupt_write(hd, 0x01, (char *)msg, len, 1000);
      printf("%s: usb_interrupt_write(request capabilities) = %d\n", r == len ? "OK" : "FAIL", r); if (r != len) ok = 0;
      if (!wait_flag(&got_caps, 2000)) { printf("FAIL: async reader got no capabilities reply\n"); ok = 0; }
      len = ant_msg(msg, 0x42, assign, 3);     /* assign channel 0, bidirectional slave, network 0 */
      r = usb_interrupt_write(hd, 0x01, (char *)msg, len, 1000);
      printf("%s: usb_interrupt_write(assign channel 0) = %d\n", r == len ? "OK" : "FAIL", r); if (r != len) ok = 0;
      if (wait_flag(&got_assign, 2000) != 1) { printf("FAIL: no RESPONSE_NO_ERROR for assign channel\n"); ok = 0; }
      else printf("OK: channel 0 assigned (this is what failed inside Zwift)\n");
      len = ant_msg(msg, 0x41, unassign, 1);
      usb_interrupt_write(hd, 0x01, (char *)msg, len, 1000);
      wait_flag(&got_unassign, 2000);
      rx_stop = 1; WaitForSingleObject(th, 3000);
      usb_free_async(&rx_ctx);
      usb_release_interface(hd, 0); usb_close(hd);
      printf(ok ? "OK: async receive + concurrent writes work - Zwift's ANT+ path is fixed\n" : "FAIL: async ANT path broken\n");
      return ok ? 0 : 8;
    }
  }
}

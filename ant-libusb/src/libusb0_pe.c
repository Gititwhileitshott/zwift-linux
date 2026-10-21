/* Windows (PE) side of libusb0.dll for Wine.
 * Exports the libusb-win32 API and forwards every call to the native Linux
 * implementation (unixlib.c -> libusb0.so) via Wine's unix-call dispatcher. */
#include <windows.h>
#include <winternl.h>
#include "calls.h"

typedef UINT64 unixlib_handle_t;
#define MemoryWineUnixFuncs 1000
extern IMAGE_DOS_HEADER __ImageBase;

static unixlib_handle_t unix_handle;
static NTSTATUS (WINAPI *unix_dispatch)(unixlib_handle_t, unsigned int, void *);

static BOOL init_unix(void)
{
  typedef NTSTATUS (WINAPI *qvm_t)(HANDLE, PVOID, ULONG, PVOID, SIZE_T, SIZE_T *);
  HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
  void **disp = (void **)GetProcAddress(ntdll, "__wine_unix_call_dispatcher");
  qvm_t qvm = (qvm_t)GetProcAddress(ntdll, "NtQueryVirtualMemory");
  if (!disp || !qvm) return FALSE;            /* not running on Wine */
  unix_dispatch = (NTSTATUS (WINAPI *)(unixlib_handle_t, unsigned int, void *))*disp;
  return !qvm(GetCurrentProcess(), &__ImageBase, MemoryWineUnixFuncs, &unix_handle, sizeof(unix_handle), NULL);
}

static long long call(enum libusb0_call code, struct libusb0_args *a)
{
  if (!unix_handle) return -1;
  unix_dispatch(unix_handle, code, a);
  return a->ret;
}

#define A(...) struct libusb0_args a = { { __VA_ARGS__ }, 0 }
#define U64(x) ((unsigned long long)(ULONG_PTR)(x))
#define API __declspec(dllexport) __cdecl

struct usb_version { struct { int major, minor, micro, nano; } dll, driver; };
static const struct usb_version version = { { 1, 2, 6, 0 }, { 1, 2, 6, 0 } };

void  API usb_init(void)                 { A(0); call(call_usb_init, &a); }
void  API usb_set_debug(int l)           { A(U64(l)); call(call_usb_set_debug, &a); }
int   API usb_find_busses(void)          { A(0); return (int)call(call_usb_find_busses, &a); }
int   API usb_find_devices(void)         { A(0); return (int)call(call_usb_find_devices, &a); }
void *API usb_get_busses(void)           { A(0); return (void *)(ULONG_PTR)call(call_usb_get_busses, &a); }
void *API usb_open(void *dev)            { A(U64(dev)); return (void *)(ULONG_PTR)call(call_usb_open, &a); }
int   API usb_close(void *h)             { A(U64(h)); return (int)call(call_usb_close, &a); }
void *API usb_device(void *h)            { A(U64(h)); return (void *)(ULONG_PTR)call(call_usb_device, &a); }
const char *API usb_strerror(void)       { A(0); return unix_handle ? (const char *)(ULONG_PTR)call(call_usb_strerror, &a) : "libusb0: not running on Wine"; }
const struct usb_version *API usb_get_version(void) { return &version; }

int API usb_get_string(void *h, int i, int lang, char *b, size_t n) { A(U64(h), U64(i), U64(lang), U64(b), U64(n)); return (int)call(call_usb_get_string, &a); }
int API usb_get_string_simple(void *h, int i, char *b, size_t n)  { A(U64(h), U64(i), U64(b), U64(n)); return (int)call(call_usb_get_string_simple, &a); }
int API usb_get_descriptor_by_endpoint(void *h, int ep, unsigned char t, unsigned char i, void *b, int n)
  { A(U64(h), U64(ep), U64(t), U64(i), U64(b), U64(n)); return (int)call(call_usb_get_descriptor_by_endpoint, &a); }
int API usb_get_descriptor(void *h, unsigned char t, unsigned char i, void *b, int n)
  { A(U64(h), U64(t), U64(i), U64(b), U64(n)); return (int)call(call_usb_get_descriptor, &a); }

#define XFER(n) int API n(void *h, int ep, char *b, int sz, int to) { A(U64(h), U64(ep), U64(b), U64(sz), U64(to)); return (int)call(call_##n, &a); }
XFER(usb_bulk_write) XFER(usb_bulk_read) XFER(usb_interrupt_write) XFER(usb_interrupt_read)

int API usb_control_msg(void *h, int rt, int rq, int v, int i, char *b, int sz, int to)
  { A(U64(h), U64(rt), U64(rq), U64(v), U64(i), U64(b), U64(sz), U64(to)); return (int)call(call_usb_control_msg, &a); }

#define I1(n) int API n(void *h, int x) { A(U64(h), U64(x)); return (int)call(call_##n, &a); }
I1(usb_set_configuration) I1(usb_claim_interface) I1(usb_release_interface) I1(usb_set_altinterface)
int API usb_resetep(void *h, unsigned int ep)    { A(U64(h), U64(ep)); return (int)call(call_usb_resetep, &a); }
int API usb_clear_halt(void *h, unsigned int ep) { A(U64(h), U64(ep)); return (int)call(call_usb_clear_halt, &a); }
int API usb_reset(void *h)                       { A(U64(h)); return (int)call(call_usb_reset, &a); }
int API usb_reset_ex(void *h, unsigned int f)    { (void)f; return usb_reset(h); }

int API usb_bulk_setup_async(void *h, void **ctx, unsigned char ep) { A(U64(h), U64(ctx), U64(ep)); return (int)call(call_usb_bulk_setup_async, &a); }
int API usb_submit_async(void *ctx, char *b, int sz) { A(U64(ctx), U64(b), U64(sz)); return (int)call(call_usb_submit_async, &a); }
int API usb_reap_async(void *ctx, int to)            { A(U64(ctx), U64(to)); return (int)call(call_usb_reap_async, &a); }
int API usb_reap_async_nocancel(void *ctx, int to)   { A(U64(ctx), U64(to)); return (int)call(call_usb_reap_async_nocancel, &a); }
int API usb_free_async(void **ctx)                   { A(U64(ctx)); return (int)call(call_usb_free_async, &a); }
int API usb_cancel_async(void *ctx)                  { A(U64(ctx)); return (int)call(call_usb_cancel_async, &a); }

/* marker so tools can tell this bridge from the real libusb-win32 DLL */
const char *API libusb0_wine_bridge_version(void) { return "libusb0-wine-bridge 0.2"; }

/* libusb-win32 driver-management / unsupported exports: harmless stubs so
 * applications that import them still load. */
int API usb_isochronous_setup_async(void *h, void **c, unsigned char ep, int ps) { (void)h; (void)c; (void)ep; (void)ps; return -1; }
int API usb_interrupt_setup_async(void *h, void **c, unsigned char ep) { (void)h; (void)c; (void)ep; return -1; }
int API usb_install_service_np(void) { return 0; }
int API usb_uninstall_service_np(void) { return 0; }
int API usb_install_driver_np(const char *inf) { (void)inf; return 0; }
int API usb_touch_inf_file_np(const char *inf) { (void)inf; return 0; }
BOOL API usb_install_needs_restart_np(void) { return FALSE; }
int API usb_install_npW(HWND w, HINSTANCE i, LPCWSTR c, int s) { (void)w; (void)i; (void)c; (void)s; return 0; }
int API usb_install_npA(HWND w, HINSTANCE i, LPCSTR c, int s) { (void)w; (void)i; (void)c; (void)s; return 0; }
void CALLBACK usb_install_service_np_rundll(HWND w, HINSTANCE i, LPSTR c, int s) { (void)w; (void)i; (void)c; (void)s; }
void CALLBACK usb_uninstall_service_np_rundll(HWND w, HINSTANCE i, LPSTR c, int s) { (void)w; (void)i; (void)c; (void)s; }
void CALLBACK usb_install_driver_np_rundll(HWND w, HINSTANCE i, LPSTR c, int s) { (void)w; (void)i; (void)c; (void)s; }
void CALLBACK usb_touch_inf_file_np_rundll(HWND w, HINSTANCE i, LPSTR c, int s) { (void)w; (void)i; (void)c; (void)s; }

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
  (void)reserved;
  if (reason == DLL_PROCESS_ATTACH) {
    DisableThreadLibraryCalls(inst);
    init_unix();   /* failure is reported lazily: calls return -1 */
  }
  return TRUE;
}

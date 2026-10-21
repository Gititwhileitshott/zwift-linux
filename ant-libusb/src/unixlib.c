/* Unix side of libusb0.dll for Wine: runs the libusb-wine (libusb-0.1 / usbfs)
 * implementation natively and exposes it through Wine's unix-call table. */
#include <stdint.h>
#include "usb.h"
#include "calls.h"

typedef int NTSTATUS;
#define P(i)  ((void *)(uintptr_t)c->a[i])
#define I(i)  ((int)c->a[i])
#define U(i)  ((unsigned int)c->a[i])
#define UC(i) ((unsigned char)c->a[i])
#define Z(i)  ((size_t)c->a[i])
#define RP(e) c->ret = (long long)(uintptr_t)(e)
#define RI(e) c->ret = (long long)(e)
#define T(n, body) static NTSTATUS t_##n(void *args) { struct libusb0_args *c = args; body; return 0; }

T(usb_init, usb_init())
T(usb_set_debug, usb_set_debug(I(0)))
T(usb_find_busses, RI(usb_find_busses()))
T(usb_find_devices, RI(usb_find_devices()))
T(usb_get_busses, RP(usb_get_busses()))
T(usb_open, RP(usb_open(P(0))))
T(usb_close, RI(usb_close(P(0))))
T(usb_device, RP(usb_device(P(0))))
T(usb_strerror, RP(usb_strerror()))
T(usb_get_string, RI(usb_get_string(P(0), I(1), I(2), P(3), Z(4))))
T(usb_get_string_simple, RI(usb_get_string_simple(P(0), I(1), P(2), Z(3))))
T(usb_get_descriptor_by_endpoint, RI(usb_get_descriptor_by_endpoint(P(0), I(1), UC(2), UC(3), P(4), I(5))))
T(usb_get_descriptor, RI(usb_get_descriptor(P(0), UC(1), UC(2), P(3), I(4))))
T(usb_bulk_write, RI(usb_bulk_write(P(0), I(1), P(2), I(3), I(4))))
T(usb_bulk_read, RI(usb_bulk_read(P(0), I(1), P(2), I(3), I(4))))
T(usb_interrupt_write, RI(usb_interrupt_write(P(0), I(1), P(2), I(3), I(4))))
T(usb_interrupt_read, RI(usb_interrupt_read(P(0), I(1), P(2), I(3), I(4))))
T(usb_control_msg, RI(usb_control_msg(P(0), I(1), I(2), I(3), I(4), P(5), I(6), I(7))))
T(usb_set_configuration, RI(usb_set_configuration(P(0), I(1))))
T(usb_claim_interface, RI(usb_claim_interface(P(0), I(1))))
T(usb_release_interface, RI(usb_release_interface(P(0), I(1))))
T(usb_set_altinterface, RI(usb_set_altinterface(P(0), I(1))))
T(usb_resetep, RI(usb_resetep(P(0), U(1))))
T(usb_clear_halt, RI(usb_clear_halt(P(0), U(1))))
T(usb_reset, RI(usb_reset(P(0))))
T(usb_bulk_setup_async, RI(usb_bulk_setup_async(P(0), P(1), UC(2))))
T(usb_submit_async, RI(usb_submit_async(P(0), P(1), I(2))))
T(usb_reap_async, RI(usb_reap_async(P(0), I(1))))
T(usb_reap_async_nocancel, RI(usb_reap_async_nocancel(P(0), I(1))))
T(usb_free_async, RI(usb_free_async(P(0))))
T(usb_cancel_async, RI(usb_cancel_async(P(0))))

__attribute__((visibility("default")))
const NTSTATUS (*__wine_unix_call_funcs[])(void *) = {
#define X(n) t_##n,
  LIBUSB0_CALLS
#undef X
};

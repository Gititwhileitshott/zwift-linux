/* Shared between the PE (Windows) side and the Unix side of libusb0.dll for Wine.
 * X(name, nargs, has_return) - order defines the unix-call function codes. */
#define LIBUSB0_CALLS \
  X(usb_init) X(usb_set_debug) X(usb_find_busses) X(usb_find_devices) X(usb_get_busses) \
  X(usb_open) X(usb_close) X(usb_device) X(usb_strerror) \
  X(usb_get_string) X(usb_get_string_simple) X(usb_get_descriptor_by_endpoint) X(usb_get_descriptor) \
  X(usb_bulk_write) X(usb_bulk_read) X(usb_interrupt_write) X(usb_interrupt_read) X(usb_control_msg) \
  X(usb_set_configuration) X(usb_claim_interface) X(usb_release_interface) X(usb_set_altinterface) \
  X(usb_resetep) X(usb_clear_halt) X(usb_reset) \
  X(usb_bulk_setup_async) X(usb_submit_async) X(usb_reap_async) X(usb_reap_async_nocancel) X(usb_free_async) X(usb_cancel_async)

enum libusb0_call {
#define X(n) call_##n,
  LIBUSB0_CALLS
#undef X
  call_count
};

/* every call marshals up to 8 integer/pointer arguments and one return value */
struct libusb0_args { unsigned long long a[8]; long long ret; };

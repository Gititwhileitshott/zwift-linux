# libusb0.dll bridge for Wine/Proton (ANT+ dongles in Zwift) - v0.2

Zwift talks to ANT+ USB sticks through **libusb-win32** (`libusb0.dll` + the `libusb0.sys`
kernel driver, shipped in ZwiftSetup.exe under `Windows ANT Dongle Driver/`). Windows kernel
drivers cannot run under Wine, so Zwift finds no dongle. This bridge replaces `libusb0.dll`
with a Wine builtin that implements the same API on top of Linux usbfs:

    ZwiftApp.exe -> libusb0.dll (PE, x86_64-windows) -> Wine unix call -> libusb0.so (x86_64-unix) -> /dev/bus/usb

* `src/` – sources (Linux back-end derived from stanson-ch/libusb-wine, LGPL-2.1; see COPYING)
* `build/` – prebuilt x86_64 binaries + a placeholder DLL for the prefix's system32
* `test/antprobe.exe` – resets the stick and requests its capabilities through the bridge
* `ant-test.sh` – one-command test (fixes udev permissions, runs antprobe under Wine)

Install into a runner (Wine or Proton dir) and prefix:

    cp build/x86_64-windows/libusb0.dll <runner>/lib/wine/x86_64-windows/
    cp build/x86_64-unix/libusb0.so     <runner>/lib/wine/x86_64-unix/
    cp build/placeholder/libusb0.dll    <prefix>/drive_c/windows/system32/
    WINEDLLOVERRIDES="libusb0=b"        # Zwift's installer drops the Windows DLL in system32

v0.2 changes (needed for Zwift's ANT_DLL.dll):
* usb_interrupt_read/write are submitted as BULK URBs (usbfs rejects INTERRUPT URBs on the
  bulk endpoints ANT sticks use; libusb-win32 on Windows does not care).
* Per-URB completion dispatcher: any thread that reaps a completion hands it to its owner, so
  an async reader thread no longer steals a writer's completion.
* usb_reap_async / usb_reap_async_nocancel honour their timeout and return -116 (ETIMEDOUT)
  like libusb-win32; _nocancel leaves the request pending.

Rebuild: cd src && make -f build.mk MINGW=x86_64-w64-mingw32- WINEBUILD=winebuild
(needs a mingw-w64 cross compiler, Wine's winebuild for the placeholder, and a host C compiler).

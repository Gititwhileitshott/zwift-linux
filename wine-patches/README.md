# winebth.sys: retry StartNotify (heart rate "connected, no signal")

Zwift turns on heart-rate notifications once per connection. Under Wine that request (BlueZ
`StartNotify`, a CCCD write) sometimes fails, for example with
`Operation failed with ATT error: 0x0e` from a Garmin fenix 7 right after connecting. Zwift then
logs `[BLEWinLib] Set notify failed`, shows the sensor as connected, and never gets a reading.
On the same connection a later `StartNotify` succeeds and the watch sends heart rate normally,
so the request only needs repeating.

`winebth-start-notify-retry.patch` makes Wine's Bluetooth driver (`dlls/winebth.sys/dbus.c`, the
Linux side of `winebth.sys`) retry a failed `StartNotify` up to 6 times, 400 ms apart, when BlueZ
answers `org.bluez.Error.Failed` or `org.bluez.Error.InProgress`. The patch is against
GE-Proton 11-8's Wine: [ValveSoftware/wine](https://github.com/ValveSoftware/wine) commit
`981e2f0b9007fd70a6e0ed6119cb18f4164e26f9` with GE-Proton's
`patches/wine-hotfixes/bluetooth-le/` series applied.

`winebth.so` is that file built for GE-Proton 11-8 (x86_64, needs glibc 2.38, which Proton's
steamrt4 runtime provides). `install.sh` installs it only when the runner's own `winebth.so` is
the unmodified GE-Proton 11-8 build (SHA-256 `54e85a75a9ed092a548a97204dc2f0a99bb5c7a48ce5a3f9b503887b84c4a3f2`)
and keeps that file as `winebth.so.orig` next to it. Restore it with:

    cp ~/.local/share/zwift-linux/GE-Proton11-8-x86_64/files/lib/wine/x86_64-unix/winebth.so.orig \
       ~/.local/share/zwift-linux/GE-Proton11-8-x86_64/files/lib/wine/x86_64-unix/winebth.so

`tools/ble-hr-hold.py`, which `zwift` starts with every session, is the other half of the fix: it
holds a heart-rate subscription of its own, so BlueZ can answer Zwift's request without another
write to the sensor.

## Rebuild

Only the Linux library changes, so the whole of Wine doesn't need building:

    git -C wine fetch --depth 1 origin 981e2f0b9007fd70a6e0ed6119cb18f4164e26f9 && git -C wine checkout FETCH_HEAD
    for p in proton-ge-custom/patches/wine-hotfixes/bluetooth-le/*.patch; do git -C wine apply "$PWD/$p"; done
    git -C wine apply "$PWD/wine-patches/winebth-start-notify-retry.patch"
    (cd wine && autoreconf -f && mkdir -p ../build && cd ../build && ../wine/configure --enable-win64 --without-mingw --without-x)
    # configure stops at "could not create Makefile" in this tree; include/config.h is all that is needed
    mkdir -p build/dlls/winebth.sys && cd build/dlls/winebth.sys
    for f in dbus unixlib; do
      gcc -c -o $f.o ../../../wine/dlls/winebth.sys/$f.c -I../../../wine/dlls/winebth.sys -I../../include \
        -I../../../wine/include -D__WINESRC__ -DWINE_UNIX_LIB -D_REENTRANT -fPIC -fasynchronous-unwind-tables \
        -fno-strict-aliasing -fvisibility=hidden -O2 $(pkg-config --cflags dbus-1)
    done
    gcc -shared -Wl,-soname,winebth.so -Wl,-z,defs -o winebth.so dbus.o unixlib.o \
      -L<GE-Proton11-8>/files/lib/wine/x86_64-unix -l:ntdll.so

Tested on the "workout" PC (CachyOS, GNOME, MediaTek MT7922 Bluetooth, fenix 7) on 10 November
2026: a 68-minute ride with heart rate throughout, and three early drops that Zwift reconnected by
itself. In that session the first request already succeeded, so the retry itself did not run.

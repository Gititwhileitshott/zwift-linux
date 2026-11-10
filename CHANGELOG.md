# Changelog

## 10 November 2026

- **Bluetooth heart-rate sensors that connect but show "no signal" are fixed.** With a Garmin
  fenix 7, Zwift logged `[BLEWinLib] Set notify failed` and never received a pulse. Wine's
  request to BlueZ to switch on heart-rate notifications (`StartNotify`) failed with
  `ATT error: 0x0e` around connection setup, and Zwift doesn't repeat it. On the same
  connection the watch sent heart rate normally (120 readings a minute) as soon as the request
  was made again, so the sensor, BlueZ and the kernel were fine.
  - `zwift` now starts `tools/ble-hr-hold.py`, which holds its own heart-rate subscription for
    any connected heart-rate sensor while Zwift runs (`ble-hr-hold.log` in the data folder).
  - `wine-patches/` adds a retry for `StartNotify` to Wine's Bluetooth driver (up to 6 tries,
    400 ms apart). `install.sh` installs the prebuilt `winebth.so` only over the unmodified
    GE-Proton 11-8 file and keeps that as `winebth.so.orig`.
  - Tested on the "workout" PC: a 68-minute ride with heart rate throughout, and Zwift
    reconnected the fenix by itself after three short early drops. The retry didn't run in that
    session, because the first request succeeded.
  - `tools/ble-watch.py` logs what BlueZ sees for one sensor during a ride (connects, BlueZ's
    disconnect reason, notification gaps), without root.
- **Zwift's window keeps its size and position.** Zwift saves neither. `tools/zwift-window.py`
  runs alongside the game and, with Wine's X11 driver, restores the last size and position. If
  that spot is no longer on any monitor, it restores only the size, shrunk to fit if needed. With
  every driver, including Wayland, the last size Zwift logged is written to `prefs.xml` after the
  game closes, so the next start opens at that size.
- **`zwift doctor` no longer reports a working ANT+ stick as failed.** umu/Proton doesn't pass a
  Windows program's console output back, so the live stick test always looked empty. The test now
  writes its output to a file.

## 2 November 2026

- **Repository hardening.** Added `SECURITY.md` (report problems privately through GitHub),
  `CODEOWNERS`, Dependabot for GitHub Actions, and a CI workflow (read-only permissions, actions
  pinned to commits) that runs ShellCheck and Python syntax checks, verifies every prebuilt
  binary against its checksum and builds `LinuxZwiftLauncher.exe` from source. The ANT+ bridge
  binaries now have `ant-libusb/SHA256SUMS`, which `install.sh` checks before installing them,
  and `ant-libusb/ant-test.sh` verifies the Wine build it downloads.
- **Resolution no longer stuck at 1080p** ([#3](https://github.com/Gititwhileitshott/zwift-linux/pull/3)).
  Zwift caps the resolution by the graphics profile it picks for your GPU, and under Wine it often
  picks a low one (the medium profile, which stops at 1080p, on an AMD Renoir iGPU). GNOME's
  fractional scaling also shrinks the desktop size XWayland reports. The installer now reads the
  largest connected screen's native resolution from `/sys/class/drm` and writes it to Zwift's
  `prefs.xml` once, at the first start; a resolution you then pick in Zwift's settings sticks.
  - `./install.sh --resolution WxH` picks another resolution, `--resolution auto` leaves it to Zwift.
  - `zwift reset-resolution` removes it again (a backup of `prefs.xml` is kept).
  - `zwift set-resolution [WxH]` sets a resolution, or the native one without WxH.
  - `zwift doctor` and `./install.sh --check` show the resolution.
  - Tested: confirmed working on the AMD Renoir PC (GNOME, XWayland).
- **Installer no longer hangs at step 5 when `kscreen-doctor` is installed outside KDE**
  ([#4](https://github.com/Gititwhileitshott/zwift-linux/pull/4), fixes
  [#2](https://github.com/Gititwhileitshott/zwift-linux/issues/2)). Without a running KScreen
  service, `kscreen-doctor` waits forever. The installer now only runs it in a KDE Plasma session
  (`XDG_CURRENT_DESKTOP` contains `KDE`, or `KDE_FULL_SESSION=true`) and stops it after 5 s, then
  falls back to the Xft.dpi and GNOME checks as before.
  - Not yet tested on a real KDE desktop. KDE reports are welcome; include `zwift doctor` output.

## 1.1.0 (October 2026)

- Runs Zwift without the Windows launcher, which stopped working under Wine with launcher 1.2.0
  ([#1](https://github.com/Gititwhileitshott/zwift-linux/pull/1)). See the README.

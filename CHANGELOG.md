# Changelog

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

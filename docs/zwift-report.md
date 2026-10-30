# Zwift for Windows on Linux: what breaks under Wine, and what fixes it

Prepared for Zwift, Inc. by the zwift-linux project. Draft, last updated 30 Oct 2026.

> **Status of this draft.** Sections marked **(pending)** describe work that is still in progress.
> They list the question being answered, not a result. Nothing in them should be read as verified
> until the section is filled in.

## Summary

- Zwift for Windows runs on Linux through Wine/Proton without modifying any of Zwift's files.
  Up to launcher 1.1.18 it ran with Bluetooth LE and ANT+ trainers connected directly
  (verified 13 Oct 2026, details below).
- Launcher 1.2.0 (built 15 Oct 2026) stopped working under GE-Proton 11-8. Its login screen uses
  WebView2's composition control, which needs WinRT types (`Windows.Graphics.SizeInt32` and
  related composition APIs) that the Wine in GE-Proton 11-8 does not provide. The launcher catches
  the error, reports it to Sentry and exits about 3 seconds after starting. Newer upstream Wine
  (11.20) ships the Windows metadata that defines `SizeInt32`; whether that is enough for the
  launcher is still being tested.
- Bluetooth LE and ANT+ are solved by the existing fixes (findings 4 and 5) and need no further work.
- Logging in works without the launcher: a native sign-in plus a small starter runs ZwiftApp 1.124.0 directly (finding 2).
- A ride in Watopia ran at a steady 58 FPS (findings 2 and 3).
- The launcher's HTTPS calls work once .NET is allowed to use modern TLS (finding 6).
- On NVIDIA under GNOME, the game needs Wine's native Wayland driver; under XWayland the picture froze (finding 3).
- **(in progress)** Getting launcher 1.2.0's own login screen to run (finding 1).

## Test setup

| | |
| --- | --- |
| Distro / kernel | CachyOS, Linux 7.2.9 |
| GPU | AMD Radeon 890M (Mesa) |
| Runner | GE-Proton 11-8 via umu-launcher 1.4.4 (`GAMEID=umu-zwift`) |
| Zwift | Game 1.123.0 (build 167050); launcher 1.1.18 (working) and 1.2.0 (failing) |
| Second PC | NVIDIA RTX 4090, ZwiftApp 1.124.0 (native login test) |
| Distros (installer checks only) | Arch, Fedora 44, Ubuntu 22.04/24.04/26.04, Debian 13, openSUSE Tumbleweed (containers) |
| Sensors | Wahoo KICKR BIKE (BLE FTMS), Garmin fenix 7 (BLE HR), Dynastream ANTUSB-m (ANT+) |

## Findings

Each finding: what Zwift does on Windows, what happens under Wine, what fixes it, and what Zwift
could change on its side to make Linux (and Wine-based setups like Steam Deck) more robust.

### 1. Launcher 1.2.0 exits at startup (WebView2 composition control)

- **Windows behaviour:** the launcher hosts its login page in
  `Microsoft.Web.WebView2.Wpf.WebView2CompositionControl`.
- **Under Wine (GE-Proton 11-8):** `TryInitializeD3DImage()` throws
  `System.TypeLoadException: Could not find Windows Runtime type 'Windows.Graphics.SizeInt32'`.
  The launcher catches it, sends a Sentry report and exits with code 0. Setting the prefix to
  Windows 10 or updating WebView2 to 156 does not help. Launcher 1.1.18 used the standard
  `WebView2` (HWND) control and works.
- **Newer Wine:** upstream Wine 11.20 ships the Windows metadata file that defines
  `Windows.Graphics.SizeInt32`. In current testing the launcher still fails in the composition
  control, now on `Windows.UI.Composition`, which Wine doesn't implement.
- **Fix:** **(in progress)** a shim that makes the launcher use the classic window-based WebView2
  control instead of the composition control. Until it lands, the native login in finding 2 starts
  the game without the launcher.
- **Zwift-side suggestion:** fall back to the HWND-based `WebView2` control when composition
  initialisation fails, instead of exiting. This would also cover Windows machines with broken
  graphics drivers.

### 2. Logging in without the launcher's web view

- **Question:** can a user sign in to Zwift on Linux if the launcher's embedded browser can't run?
- **Result (30 Oct 2026):** yes. `share/zwift-auth.py` repeats the launcher's OpenID Connect sign-in
  against Zwift's Keycloak server (client `Game_Launcher`, redirect `http://zwift/`), showing
  Zwift's own sign-in page in a WebKitGTK window with a throwaway session. It exchanges the code at
  the token endpoint and keeps only the refresh token (mode 600). `LinuxZwiftLauncher.exe`
  (`zwift-start/zwift-start.c`) then starts ZwiftApp.exe with the launcher's exact command line,
  `"ZwiftApp.exe" --launcher_version=<v> --token=<token JSON>`, through `CreateProcessW`, so the
  JSON's quotes reach the game unescaped. The token file is deleted as soon as it has been read. The game
  files came straight from Zwift's CDN, so the launcher was not needed at all. ZwiftApp 1.124.0
  under GE-Proton 11-8 logged in, loaded the rider profile, and ran with OpenGL 4.6 and working
  audio on the first try.
- **Parent-process check:** ZwiftApp checks that its parent process path contains
  `ZwiftLauncher.exe`, `ZwiftHelper.exe` or `devenv.exe`. If it doesn't, ZwiftApp starts
  `ZwiftLauncher.exe` and exits, or shows "ERROR ZA1" when that fails. Our starter is therefore
  named `LinuxZwiftLauncher.exe` and built as a GUI-subsystem program, so no console window opens.
- **Ride test:** a ride in Watopia with this login ran at a steady 58 FPS.
- **Zwift-side suggestion:** a supported way to start ZwiftApp with a token from a system browser
  login (device-code or loopback redirect), without the parent-process check, would remove the
  need for the embedded launcher on Linux and Steam Deck.

### 3. Game performance

- **Known so far:** 55-93 FPS on a Radeon 890M with Zwift 1.123.0 under GE-Proton 11-7/11-8.
- **Current build:** ZwiftApp 1.124.0 under GE-Proton 11-8 on an NVIDIA RTX 4090 ran at about
  58 FPS with vsync on (so capped by the display).
- **Ride:** steady 58 FPS riding in Watopia.
- **Frozen display on NVIDIA under XWayland:** on a GNOME Wayland desktop with an NVIDIA GPU,
  running the game through XWayland left the picture frozen (frames never reached the screen) and
  GNOME reported the window (`steam_app_0`) as not responding.
- **Fix:** run the game with Wine's native Wayland driver instead of XWayland. With that, the
  menus, watching another rider and exiting all worked normally.
- **Other setups:** zwift-linux picks the display driver from the session and GPU (Wayland driver
  for NVIDIA 595+ on Wayland, XWayland for Mesa GPUs and older NVIDIA, X11 on X11 sessions) and
  falls back to the other one if OpenGL fails to start. The tested and untested combinations are
  listed in [COMPATIBILITY.md](../COMPATIBILITY.md); AMD on the current build, KDE, wlroots
  desktops and Intel GPUs are still untested.
- **Known limitation:** with Wine's Wayland driver, the game drops to about 1 FPS while another
  window fully covers it (the compositor stops sending frame callbacks) and recovers when visible.
- **Ride-highlight recording:** clips can't be saved because Proton's media back-end (`winedmo`)
  has no MP4 muxer, and Zwift retries the encoder several times a second on both display drivers.
  zwift-linux turns it off (`VIDEO_CAPTURE_ENABLED=0` in `prefs.xml`).
- **Rendering notes:** ZwiftApp draws with OpenGL (GL 4.6 compatibility profile); D3D11 is only used
  for Media Foundation video decode, whose hardware probe fails under Wine, so video is decoded
  in software.
- **Zwift-side suggestions:** stop retrying the video encoder after it fails a few times, and fall
  back to software decode without repeated probing.

### 4. Bluetooth LE trainers and sensors

- **Windows behaviour:** `BleWin10Lib.dll` uses WinRT `Windows.Devices.Bluetooth` and
  `Windows.Devices.Radios`.
- **Under stock Wine:** not implemented, so no Bluetooth devices appear.
- **Fix:** GE-Proton 11-8 includes Wine Bluetooth LE support (`winebth`, enabled with
  `PROTON_ENABLE_WINEBTH=1`). Verified with the KICKR BIKE (power, cadence, controllable
  trainer, full rides with grade changes) and fenix 7 HR.
- **Pitfall found:** after a session ends mid-connection, BlueZ can refuse `StartDiscovery` with
  `org.bluez.Error.InProgress`. Wine logs it and Zwift never retries, so the pairing screen stays
  empty. zwift-linux test-scans before launch and power-cycles the adapter when it's stuck.
- **Zwift-side suggestion:** retry starting the BLE watcher if it fails to start, rather than
  treating the first failure as final.

### 5. ANT+ USB sticks

- **Windows behaviour:** Dynastream `ANT_DLL.dll` talks to the stick through `libusb0.dll` and the
  `libusb0.sys` kernel driver.
- **Under Wine:** Windows kernel drivers can't load, so no stick is found.
- **Fix:** zwift-linux ships a Wine builtin `libusb0.dll` (`ant-libusb/`, LGPL) that forwards the
  libusb-win32 API to Linux usbfs. Verified: ANT+ FE-C and power devices listed with live data,
  full ride on ANT+.

### 6. HTTPS from the launcher (.NET TLS versions)

- **Under Wine:** the .NET Framework in the prefix offered only old TLS versions, so the
  launcher's requests to Zwift's HTTPS endpoints failed.
- **Fix:** set `SchUseStrongCrypto` and `SystemDefaultTlsVersions` in the prefix registry. With
  these, Zwift's HTTPS endpoints are reachable.
- **Zwift-side suggestion:** have the launcher request TLS 1.2+ explicitly instead of relying on
  the system default.

### 7. Smaller issues

- `.NET 4.8` and WebView2 must be real Microsoft installs; with wine-mono the launcher exits with
  code 200. GE-Proton's `umu-zwift` fix installs them.
- `combase.RoUnregisterForApartmentShutdown` is missing in Wine and causes a harmless abort after
  Zwift closes.
- Zwift's updater can restore the Windows `libusb0.dll`; zwift-linux puts its placeholder back
  before each launch.

## What Zwift could do

Collected from the suggestions above, smallest change first:

1. Fall back to the HWND `WebView2` control when the composition control fails (finding 1).
2. Retry the BLE watcher start on failure (finding 4).
3. Support starting the game with a token from a system browser login (finding 2).
4. Request TLS 1.2+ explicitly in the launcher (finding 6).
5. Stop retrying the video encoder after repeated failures (finding 3).
6. **(pending)** further items from the launcher, login and performance work.

## How to reproduce

```bash
git clone https://github.com/Gititwhileitshott/zwift-linux.git
cd zwift-linux && ./install.sh
zwift doctor
```

Debug logging for Bluetooth:
`PROTON_LOG=+winebth,+bluetooth,+bluetoothapis,+radios,err+plugplay zwift`

## Credits

GE-Proton Bluetooth LE work by Evan Thomas and David Szendrei. ANT+ bridge back-end derived from
stanson-ch/libusb-wine and libusb-0.1. Zwift is a trademark of Zwift, Inc.; this project is not
affiliated with or endorsed by Zwift.

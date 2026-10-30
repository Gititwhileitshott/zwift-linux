# Zwift for Windows on Linux: what breaks under Wine, and what fixes it

Prepared for Zwift, Inc. by the zwift-linux project. Draft, last updated 30 Oct 2026.

> **Status of this draft.** Sections marked **(pending)** describe work that is still in progress.
> They list the question being answered, not a result. Nothing in them should be read as verified
> until the section is filled in.

## Summary

- Zwift for Windows runs on Linux through Wine/Proton without being decompiled or modified.
  Up to launcher 1.1.18 it ran with Bluetooth LE and ANT+ trainers connected directly
  (verified 13 Oct 2026, details below).
- Launcher 1.2.0 (built 15 Oct 2026) stopped working under GE-Proton 11-8. Its login screen uses
  WebView2's composition control, which needs WinRT types (`Windows.Graphics.SizeInt32` and
  related composition APIs) that the Wine in GE-Proton 11-8 does not provide. The launcher catches
  the error, reports it to Sentry and exits about 3 seconds after starting. Newer upstream Wine
  (11.20) ships the Windows metadata that defines `SizeInt32`; whether that is enough for the
  launcher is still being tested.
- Bluetooth LE and ANT+ are solved by the existing fixes (findings 4 and 5) and need no further work.
- **(pending)** Fix for launcher 1.2.0, login, and game performance on the current build.

## Test setup

| | |
| --- | --- |
| Distro / kernel | CachyOS, Linux 7.2.9 |
| GPU | AMD Radeon 890M (Mesa) |
| Runner | GE-Proton 11-8 via umu-launcher 1.4.4 (`GAMEID=umu-zwift`) |
| Zwift | Game 1.123.0 (build 167050); launcher 1.1.18 (working) and 1.2.0 (failing) |
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
  `Windows.Graphics.SizeInt32`. Not yet confirmed whether the launcher gets past this point with it.
- **Fix:** **(pending, milestone "Get WebView2 launcher working in Wine")**
- **Zwift-side suggestion:** fall back to the HWND-based `WebView2` control when composition
  initialisation fails, instead of exiting. This would also cover Windows machines with broken
  graphics drivers.

### 2. Logging in without the launcher's web view

- **Question:** can a user sign in to Zwift on Linux if the launcher's embedded browser can't run?
- **Result:** **(pending, milestone "Build our own Zwift login")**

### 3. Game performance

- **Known so far:** 55-93 FPS on a Radeon 890M with Zwift 1.123.0 under GE-Proton 11-7/11-8.
- **Result on the current build:** **(pending, milestone "Get Zwift game running smoothly")**

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

### 6. Smaller issues

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
3. **(pending)** further items from the launcher, login and performance work.

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

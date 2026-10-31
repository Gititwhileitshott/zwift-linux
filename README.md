# Zwift on Linux (zwift-linux)

Run the official **Zwift for Windows** app on Linux, with your **Bluetooth and ANT+** trainers, power meters and heart-rate monitors connecting directly. No phone bridge needed.

> Unofficial community project. Not made, supported or endorsed by Zwift, Inc. You need your own Zwift account. Zwift itself is downloaded from Zwift's own servers and is not modified.

> [!NOTE]
> **October 2026: works again, without Zwift's Windows launcher.** Zwift's launcher 1.2.0 (built October 15, 2026) closes about 3 seconds after it opens under Wine/Proton, because its login screen uses a WebView2 control that needs Windows graphics APIs Wine doesn't have. zwift-linux 1.1.0 no longer needs the launcher: `zwift` signs you in on Zwift's own sign-in page and starts the game directly, and the installer downloads the game straight from Zwift's servers. Verified on an NVIDIA RTX 4090 (GNOME, Wayland) with a ride in Watopia at a steady 58 FPS. The display settings are chosen per desktop session and GPU; see [COMPATIBILITY.md](COMPATIBILITY.md) for what has and hasn't been tested. A fresh install on an AMD Radeon 890M PC (GNOME, XWayland) also worked, with a 41-minute ride on Bluetooth heart rate. See [Signing in without the launcher](#signing-in-without-the-launcher).

## Project overview

Zwift has no Linux version. The Windows version can run through **Wine** (the Windows compatibility layer behind Steam's Proton), but out of the box Bluetooth trainers, ANT+ USB sticks and Zwift's launcher all fail. This project puts the fixes together into one installer:

- **GE-Proton 11-8**, a community build of Proton that added Bluetooth LE support for Zwift, runs the game.
- **umu-launcher** starts Proton outside of Steam, the same way Steam would.
- A small **ANT+ bridge** (`ant-libusb/`, included with source) lets Zwift's ANT+ code reach USB ANT+ sticks through Linux.
- A **`zwift` command** starts the game and quietly fixes the most common Linux Bluetooth glitch (scanning that silently fails after a crash), plus helper commands to check and repair your setup.

The result: the unmodified Windows app runs with Bluetooth and ANT+ working directly.

## Quick start for Linux beginners

You will copy and paste a few commands into a **terminal** (a window where you type commands). Everything installs into your own home folder; your password is asked for only once, for two optional system settings.

**What you need:** a 64-bit PC running Linux, an internet connection (about 6 GB of downloads), a Bluetooth adapter and/or an ANT+ USB stick, and your Zwift login.

**1. Open a terminal.** On most desktops press `Ctrl` + `Alt` + `T`, or open your app menu and search for "Terminal".

**2. Download zwift-linux.** On this GitHub page, click the green **Code** button, then **Download ZIP**. Open your Downloads folder, right-click the ZIP and choose **Extract Here**.

**3. Go into the folder.** In the terminal, type (the folder name ends in `-main` when it comes from a ZIP):

```bash
cd ~/Downloads/zwift-linux-main
```

**4. Run the installer:**

```bash
bash install.sh
```

The installer explains each step as it goes. Things to expect:
- It downloads GE-Proton (about 560 MB). Downloads are checked against official checksums.
- It asks for your password once (`sudo`) to allow ANT+ USB sticks and to switch on Bluetooth. Typing your password shows nothing on screen; that's normal.
- The first setup installs Windows components (.NET, fonts) and **takes several minutes**. If a box says `rundll32.exe - This application could not be started`, click **No**.
- It installs Zwift's launcher files, then **downloads the game directly from Zwift** (about 5 GB the first time). Nothing to click; just wait.
- When you see **"Zwift is ready."** you're done. If it lists commands under "run these yourself", copy and paste them into the terminal.

**5. Ride.** Open **Zwift** from your app menu, or type `zwift` in a terminal. The first time, a small window shows Zwift's sign-in page. Log in, and your Bluetooth and ANT+ devices appear on the pairing screen just like on Windows. If you use an ANT+ stick, unplug it and plug it back in once after installing.

**Tips**
- Make sure your trainer and sensors aren't connected to another app or your phone (Zwift Companion, Wahoo, Garmin Connect), because many only allow one connection at a time.
- If anything goes wrong, run `zwift doctor` in a terminal. It checks your Bluetooth, ANT+ stick and install and tells you what's wrong.
- To update zwift-linux later, download the new ZIP and run `bash install.sh` again. It keeps your existing setup and only does what's needed. Zwift updates itself as usual.
- To remove everything: `bash uninstall.sh` from the same folder.

## Install with git (for experienced users)

```bash
git clone https://github.com/Gititwhileitshott/zwift-linux.git
cd zwift-linux
./install.sh
```

The installer:

1. uses your distro's `umu-launcher`, or downloads the official umu zipapp (checksum-verified);
2. downloads **GE-Proton11-8** into `~/.local/share/zwift-linux` (checksum-verified, about 560 MB);
3. adds the ANT+ bridge to that GE-Proton copy;
4. asks for `sudo` once to add udev rules for ANT+ sticks (`0fcf:1008`, `0fcf:1009`) and to keep USB Bluetooth adapters out of power saving, and to start the Bluetooth service (`--no-sudo` prints the commands instead);
5. creates the Wine prefix `~/Games/zwift`. The first run installs .NET 4.8, fonts and WebView2 automatically, which takes several minutes;
6. installs Zwift's launcher files with ZwiftSetup, then downloads or updates the game directly from Zwift's update server (about 5 GB the first time, every file checked against Zwift's manifest). `zwift` repeats this update check before each start, and skips it when offline;
7. installs the `zwift` command and an app menu entry, and sets Windows DPI from your desktop scale.

Re-running `./install.sh` updates an existing install and skips finished steps.

`./install.sh --check` only checks your PC (distro, Python, sign-in window, Bluetooth, sandbox, display/GPU) and exits. Which desktops, GPUs and distros have been tested is in [COMPATIBILITY.md](COMPATIBILITY.md).

Options: `--check`, `--dpi N` (96 = 100%, 144 = 150%, 192 = 200%), `--prefix DIR`, `--setup ZwiftSetup.exe`, `--no-sudo`, `--no-ble`, `--no-ant`, `--yes`. Run `./install.sh --help`.

## Requirements

- x86_64 PC, any glibc distro: Arch, CachyOS, Manjaro, EndeavourOS, Fedora, Nobara, Bazzite, Debian, Ubuntu, Mint, Pop!_OS, openSUSE, SteamOS (desktop mode), …
- `curl`, `tar`, Python 3 (3.10+ if your distro has no `umu-launcher` package)
- For the sign-in window: WebKitGTK 6 with its Python bindings (PyGObject with GTK 4 and WebKitGTK 6.0; without them your web browser is used)
- **BlueZ** (`bluez` package; preinstalled on desktop distros) and a Bluetooth 4.0+ adapter, for Bluetooth sensors
- An ANT+ USB stick (Garmin/Dynastream USB-2 or USB-m, or compatible) for ANT+ sensors
- A GPU with working OpenGL drivers (Mesa, or NVIDIA proprietary). Zwift is CPU-bound; 6 GB VRAM recommended.
- An internet connection on the first run (umu downloads the Steam Linux Runtime from `repo.steampowered.com`)

## Commands

| Command | What it does |
| --- | --- |
| `zwift` | Start Zwift without the Windows launcher: signs in with Zwift's own sign-in page (first start, or when the sign-in expires) and starts the game directly. Before starting it checks that Bluetooth scanning works (resetting a stuck adapter); when the game exits, the tray launcher is shut down too. |
| `zwift --launcher` | Start Zwift through the Windows launcher instead (also used when the game files aren't installed yet) |
| `zwift login` / `zwift logout` / `zwift status` | Sign in again (e.g. switch account), sign out, or show whether you are signed in |
| `zwift --display x11` / `--display wayland` | Force Wine's X11 (XWayland) or Wayland driver; by default it's chosen from your session and GPU ([COMPATIBILITY.md](COMPATIBILITY.md)) |
| `zwift doctor` | Check the install, Bluetooth adapter, ANT+ stick (live test through Wine) and what the last Zwift session paired |
| `zwift kill` | Force-stop everything in the Zwift prefix |
| `zwift log` | Path of the last run's log |
| `zwift reset-bluetooth` | Forget Wine's cached Bluetooth devices (backup kept); use when Bluetooth pairing never completes |
| `./uninstall.sh [--purge]` | Remove everything; `--purge` also deletes the Zwift prefix (rides and profile are in your Zwift account) |

## What has been tested

Verified on CachyOS (kernel 7.2.9, AMD Radeon 890M), Zwift 1.123.0, 13 Oct 2026:

| Connection | Result |
| --- | --- |
| Bluetooth LE smart trainer (Wahoo KICKR BIKE, FTMS) | Power, cadence and controllable trainer; full rides with grade changes, all commands acknowledged |
| Bluetooth LE heart rate (Garmin fenix 7) | Paired and streaming |
| ANT+ USB stick (Dynastream ANTUSB-m) | Zwift lists ANT+ FE-C and power devices with live power |
| Frame rate | 55-93 FPS |

Verified on CachyOS (GNOME 51 Wayland, NVIDIA RTX 4090, driver 615.78), Zwift 1.124.0, 30 Oct 2026, with zwift-linux 1.1.0 (no Windows launcher, Wine's Wayland driver): sign-in, menus, a 10-minute ride and spectating at 58-60 FPS (vsync), clean exit. Also verified 30 Oct 2026 on a freshly installed CachyOS PC (GNOME, AMD Radeon 890M, XWayland), Zwift 1.124.0: clean install, all sensors found, and a 41-minute ride with a Garmin fenix 7 heart rate over Bluetooth once USB power saving was turned off for the Bluetooth adapter (the installer now does this).

The full desktop × GPU × distro matrix, with tested and untested setups kept apart, is in [COMPATIBILITY.md](COMPATIBILITY.md). Reports welcome: include `zwift doctor` output.

## Troubleshooting

- **Zwift window frozen, black, or "not responding":** try the other display driver: `zwift --display x11` or `zwift --display wayland`. `zwift doctor` shows which one is in use and why.
- **Launcher is tiny:** run `./install.sh --dpi 144` (150%) or `--dpi 192` (200%).
- **Bluetooth devices don't show up:** check `zwift doctor`. The adapter must be powered on (`bluetoothctl power on`) and the trainer must not be connected to another app or phone. Pairing can take 15-30 s under Wine.
- **No Bluetooth devices at all on the pairing screen:** Linux's Bluetooth service refuses to scan (`org.bluez.Error.InProgress`), typically after a session that stopped mid-connection. Zwift doesn't retry, so nothing appears. `zwift` now test-scans before each start and power-cycles the adapter if it's stuck; by hand: `bluetoothctl power off; bluetoothctl power on`. `zwift doctor` checks this too.
- **A Bluetooth sensor drops mid-ride:** USB power saving on the Bluetooth adapter can drop links. The installer adds a udev rule that turns it off; `zwift doctor` shows whether it's on. If a sensor still drops, Zwift may not reconnect it on its own (a known open issue); use ANT+ for that sensor as a fallback.
- **Bluetooth pairing starts but never completes** (Zwift falls back to ANT+ or nothing): quit Zwift, run `zwift reset-bluetooth`, then pair again. `zwift` also disconnects, at start and exit, Bluetooth devices a previous session left connected to the PC.
- **ANT+ stick not found:** run `zwift doctor`. If the device node isn't writable, re-run `./install.sh` (udev rule) and replug the stick.
- **Terminal noise:** the run log is in `zwift log`. `RoUnregisterForApartmentShutdown … aborting` after Zwift has closed is harmless (a missing stub in Wine).
- **Still stuck:** Zwift Companion bridging and Wahoo Direct Connect trainers also work.

## How it works

| Zwift on Windows uses | Under Wine | Fix |
| --- | --- | --- |
| WinRT `Windows.Devices.Bluetooth` / `Windows.Devices.Radios` (in `BleWin10Lib.dll`) | Not implemented in stock Wine | GE-Proton 11-8 BLE support (Evan Thomas, David Szendrei), `PROTON_ENABLE_WINEBTH=1` |
| Dynastream `ANT_DLL.dll` → `libusb0.dll` + `libusb0.sys` kernel driver | Wine can't load Windows kernel drivers, so no stick is found | `ant-libusb/`: a Wine builtin `libusb0.dll` that forwards the libusb-win32 API to Linux usbfs through a Wine unix library |
| .NET 4.8 + WebView2 launcher | wine-mono makes the launcher exit (code 200); launcher 1.2.0 also needs WinRT composition types Wine lacks | Not needed: `zwift-auth.py` + `LinuxZwiftLauncher.exe` do the launcher's sign-in and game start (below). GE-Proton's `umu-zwift` fix still installs .NET 4.8 and WebView2 for `zwift --launcher` |

### Signing in without the launcher

The launcher's only job before the game starts is an OpenID Connect sign-in against Zwift's Keycloak
server, which `share/zwift-auth.py` repeats with the same public endpoints and client:

1. `GET https://us-or-rly101.zwift.com/api/auth` returns the realm (`zwift`) and auth server (`https://secure.zwift.com/auth/`).
2. Zwift's sign-in page opens in a small WebKitGTK window (or your browser if WebKitGTK 6 is missing):
   `…/realms/zwift/protocol/openid-connect/auth?client_id=Game_Launcher&redirect_uri=http://zwift/&login=true&response_type=code`.
   The window uses a throwaway session, so no cookies are kept.
3. The redirect to `http://zwift/?code=…` is caught and the code is exchanged at `…/openid-connect/token`
   (`grant_type=authorization_code`, `client_id=Game_Launcher`).
4. The game is started with the launcher's exact command line,
   `"ZwiftApp.exe" --launcher_version=<v> --token=<token response JSON>` (ZwiftApp's own help text documents
   `--token=jsonToken`). `zwift-start/LinuxZwiftLauncher.exe` (source `zwift-start.c`) builds it with `CreateProcessW` because the token
   JSON's quotes must reach the game unescaped. The token is handed over in a mode-600 file that the helper
   deletes as soon as it has read it.

The refresh token is kept in `~/.local/share/zwift-linux/auth.json` (mode 600) so later starts skip the
sign-in page; `zwift logout` ends the session at Zwift and deletes it. Your password is only ever typed
into Zwift's own page. `zwift-auth.py` always verifies Zwift's TLS certificates and has no proxy option. `tools/record-login.py` is a
developer-only mitmproxy addon (not installed) that logs the real launcher's traffic with passwords, codes
and tokens removed, for checking the flow against a new launcher.

The ANT+ bridge source is in `ant-libusb/src`; `ant-libusb/test/antprobe.exe` reproduces Zwift's access pattern (async reads plus interrupt writes) against a real stick.

## Report for Zwift

[docs/zwift-report.md](docs/zwift-report.md) explains, for Zwift's developers, what fails under Wine and what fixes it. It is a draft and is updated as the remaining work lands.

## Licences and credits

- Scripts: MIT (`LICENSE`).
- `ant-libusb`: LGPL-2.1-or-later (`ant-libusb/src/COPYING`). The Linux USB back-end derives from [stanson-ch/libusb-wine](https://github.com/stanson-ch/libusb-wine) and libusb-0.1.
- GE-Proton, umu-launcher and Wine are downloaded from their official releases under their own licences.
- Zwift is a trademark of Zwift, Inc. This project is not affiliated with or endorsed by Zwift. You need your own Zwift account.

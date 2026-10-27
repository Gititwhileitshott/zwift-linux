# Zwift on Linux (zwift-linux)

Run the official **Zwift for Windows** app on Linux, with your **Bluetooth and ANT+** trainers, power meters and heart-rate monitors connecting directly. No phone bridge needed.

> Unofficial community project. Not made, supported or endorsed by Zwift, Inc. You need your own Zwift account. Zwift itself is downloaded from Zwift's own servers and is not modified.

> [!WARNING]
> **Not working at the moment (October 2026).** Zwift's launcher update 1.2.0 (built October 15, 2026) broke this project. Zwift requires the launcher to log in, and the new launcher closes about 3 seconds after it opens under Wine/Proton. The installer still finishes and prints "Zwift is ready.", but the game never downloads and you can't log in.
>
> **Why:** the new launcher draws its login screen with a newer type of embedded web view (WebView2's composition control). That control depends on a Windows graphics API (Windows.Graphics) that Wine doesn't implement yet, so the launcher fails during startup and exits. Earlier launcher versions used the standard WebView2 control, which works under Wine.
>
> **What's next:** we plan to add the missing Windows graphics API to Wine. The other route is a fallback in Zwift's launcher to the standard WebView2 control when the composition control can't start. Until one of those lands, please don't rely on this installer. Existing installs that still have an older launcher may keep working until the launcher updates itself.

## Project overview

Zwift has no Linux version. The Windows version can run through **Wine** (the Windows compatibility layer behind Steam's Proton), but out of the box Bluetooth trainers, ANT+ USB sticks and Zwift's launcher all fail. This project puts the fixes together into one installer:

- **GE-Proton 11-8**, a community build of Proton that added Bluetooth LE support for Zwift, runs the game.
- **umu-launcher** starts Proton outside of Steam, the same way Steam would.
- A small **ANT+ bridge** (`ant-libusb/`, included with source) lets Zwift's ANT+ code reach USB ANT+ sticks through Linux.
- A **`zwift` command** starts the game and quietly fixes the most common Linux Bluetooth glitch (scanning that silently fails after a crash), plus helper commands to check and repair your setup.

The result: the unmodified Windows app runs with Bluetooth and ANT+ working directly. No decompiling or reverse engineering of Zwift was needed.

## Quick start for Linux beginners

You will copy and paste a few commands into a **terminal** (a window where you type commands). Everything installs into your own home folder; your password is asked for only once, for two optional system settings.

**What you need:** a 64-bit PC running Linux, an internet connection (about 3 GB of downloads), a Bluetooth adapter and/or an ANT+ USB stick, and your Zwift login.

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
- The **Zwift launcher opens and downloads the game** (about 2 GB). When it finishes, **close the Zwift launcher window, go back to the terminal and press Enter.**
- When you see **"Zwift is ready."** you're done. If it lists commands under "run these yourself", copy and paste them into the terminal.

**5. Ride.** Open **Zwift** from your app menu, or type `zwift` in a terminal. Log in, and your Bluetooth and ANT+ devices appear on the pairing screen just like on Windows. If you use an ANT+ stick, unplug it and plug it back in once after installing.

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
4. asks for `sudo` once to add a udev rule for ANT+ sticks (`0fcf:1008`, `0fcf:1009`) and start the Bluetooth service (`--no-sudo` prints the commands instead);
5. creates the Wine prefix `~/Games/zwift`. The first run installs .NET 4.8, fonts and WebView2 automatically, which takes several minutes;
6. downloads and installs Zwift (the launcher downloads about 2 GB; close it when finished and press Enter);
7. installs the `zwift` command and an app menu entry, and sets Windows DPI from your desktop scale.

Re-running `./install.sh` updates an existing install and skips finished steps.

Options: `--dpi N` (96 = 100%, 144 = 150%, 192 = 200%), `--prefix DIR`, `--setup ZwiftSetup.exe`, `--no-sudo`, `--no-ble`, `--no-ant`, `--yes`. Run `./install.sh --help`.

## Requirements

- x86_64 PC, any glibc distro: Arch, CachyOS, Manjaro, EndeavourOS, Fedora, Nobara, Bazzite, Debian, Ubuntu, Mint, Pop!_OS, openSUSE, SteamOS (desktop mode), …
- `curl`, `tar`, Python 3.10+ (only if your distro has no `umu-launcher` package)
- **BlueZ** (`bluez` package; preinstalled on desktop distros) and a Bluetooth 4.0+ adapter, for Bluetooth sensors
- An ANT+ USB stick (Garmin/Dynastream USB-2 or USB-m, or compatible) for ANT+ sensors
- A GPU with working OpenGL drivers (Mesa, or NVIDIA proprietary). Zwift is CPU-bound; 6 GB VRAM recommended.
- An internet connection on the first run (umu downloads the Steam Linux Runtime from `repo.steampowered.com`)

## Commands

| Command | What it does |
| --- | --- |
| `zwift` | Start Zwift. Before starting it checks that Bluetooth scanning works (resetting a stuck adapter); when the game exits, the tray launcher is shut down too. |
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

Other distros use the same GE-Proton build and runtime container, so they're expected to behave the same, but haven't been tested yet. Reports welcome: include `zwift doctor` output.

## Troubleshooting

- **Launcher is tiny:** run `./install.sh --dpi 144` (150%) or `--dpi 192` (200%).
- **Bluetooth devices don't show up:** check `zwift doctor`. The adapter must be powered on (`bluetoothctl power on`) and the trainer must not be connected to another app or phone. Pairing can take 15-30 s under Wine.
- **No Bluetooth devices at all on the pairing screen:** Linux's Bluetooth service refuses to scan (`org.bluez.Error.InProgress`), typically after a session that stopped mid-connection. Zwift doesn't retry, so nothing appears. `zwift` now test-scans before each start and power-cycles the adapter if it's stuck; by hand: `bluetoothctl power off; bluetoothctl power on`. `zwift doctor` checks this too.
- **Bluetooth pairing starts but never completes** (Zwift falls back to ANT+ or nothing): quit Zwift, run `zwift reset-bluetooth`, then pair again. `zwift` also disconnects, at start and exit, Bluetooth devices a previous session left connected to the PC.
- **ANT+ stick not found:** run `zwift doctor`. If the device node isn't writable, re-run `./install.sh` (udev rule) and replug the stick.
- **Terminal noise:** the run log is in `zwift log`. `RoUnregisterForApartmentShutdown … aborting` after Zwift has closed is harmless (a missing stub in Wine).
- **Still stuck:** Zwift Companion bridging and Wahoo Direct Connect trainers also work.

## How it works

| Zwift on Windows uses | Under Wine | Fix |
| --- | --- | --- |
| WinRT `Windows.Devices.Bluetooth` / `Windows.Devices.Radios` (in `BleWin10Lib.dll`) | Not implemented in stock Wine | GE-Proton 11-8 BLE support (Evan Thomas, David Szendrei), `PROTON_ENABLE_WINEBTH=1` |
| Dynastream `ANT_DLL.dll` → `libusb0.dll` + `libusb0.sys` kernel driver | Wine can't load Windows kernel drivers, so no stick is found | `ant-libusb/`: a Wine builtin `libusb0.dll` that forwards the libusb-win32 API to Linux usbfs through a Wine unix library |
| .NET 4.8 + WebView2 launcher | wine-mono makes the launcher exit (code 200) | GE-Proton's `umu-zwift` fix installs real .NET 4.8 and WebView2 |

The ANT+ bridge source is in `ant-libusb/src`; `ant-libusb/test/antprobe.exe` reproduces Zwift's access pattern (async reads plus interrupt writes) against a real stick.

## Licences and credits

- Scripts: MIT (`LICENSE`).
- `ant-libusb`: LGPL-2.1-or-later (`ant-libusb/src/COPYING`). The Linux USB back-end derives from [stanson-ch/libusb-wine](https://github.com/stanson-ch/libusb-wine) and libusb-0.1.
- GE-Proton, umu-launcher and Wine are downloaded from their official releases under their own licences.
- Zwift is a trademark of Zwift, Inc. This project is not affiliated with or endorsed by Zwift. You need your own Zwift account.

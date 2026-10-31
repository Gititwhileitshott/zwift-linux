# Compatibility: desktops, GPUs and distros

Zwift (ZwiftApp.exe) draws with **OpenGL**. Under Wine, the GPU driver and the way Wine reaches the
desktop matter most. The distro matters very little, because the game runs inside the Steam Linux
Runtime container that umu-launcher provides, with GE-Proton 11-8.

`./install.sh --check` reports what a PC has and which path Zwift will use. `zwift doctor` shows the
same after installing.

## Display path: chosen automatically

| Session | GPU driver | Wine display driver | Why |
| --- | --- | --- | --- |
| X11 (any desktop) | any | X11 (winex11) | The only option |
| Wayland | NVIDIA 595 or newer | Wayland (winewayland) | Through XWayland on GNOME, the full-screen game renders but the window never updates ("steam_app_0 is not responding") |
| Wayland | NVIDIA older than 595 | X11 (XWayland) | winewayland is reported to freeze on NVIDIA 570 and older |
| Wayland | Mesa: AMD (radeonsi), Intel (iris), NVIDIA open (NVK/nouveau) | X11 (XWayland) | Verified working on AMD + GNOME |

To override: `zwift --display x11` or `zwift --display wayland`, or set `ZWIFT_DISPLAY=x11|wayland`.
If OpenGL fails to start on the chosen path, `zwift` writes `~/.local/share/zwift-linux/display.auto`
and uses the other path from the next start. Delete that file to go back to the default.

## Test results

| Setup | Result | Date | How |
| --- | --- | --- | --- |
| RTX 4090, NVIDIA 615.78, GNOME 51 Wayland, CachyOS, XWayland | **Fails**: game runs at 58 FPS internally, but the full-screen window never updates and input looks dead | 2026-10-30 | real ride |
| same PC, Wine Wayland driver | **Works**: menus, ride and spectating at 60 FPS (vsync); clean exit | 2026-10-30 | real ride, 10 min |
| same PC, NVIDIA through XWayland in Weston (windowed) | Works: window updates | 2026-10-30 | off-screen test |
| Mesa 26.2 (llvmpipe) through XWayland in Weston | Works: GL 4.6 compatibility profile, window updates | 2026-10-30 | off-screen test, software GL stands in for AMD/Intel |
| Mesa 26.2 (llvmpipe), Wine Wayland driver in Weston | Starts: OpenGL via EGL works; frame rate can't be judged headless | 2026-10-30 | off-screen test |
| AMD Radeon 890M, GNOME, CachyOS, XWayland, Zwift 1.123 | Works: 55-93 FPS, Bluetooth + ANT+ | 2026-10-13 | real rides |
| AMD Radeon 890M ("workout"), GNOME, fresh CachyOS, XWayland, Zwift 1.124 | **Works**: clean install, all sensors found; fenix 7 BLE HR dropped twice with USB autosuspend on, stayed connected for 41 min with it off | 2026-10-30 | real rides |
| KDE Plasma, wlroots (Sway, Hyprland), Intel GPU, NVIDIA < 595, X11 session | not tested yet; covered by the rules above | | |

## Distros

The game's runtime is the same everywhere (Steam Linux Runtime + GE-Proton). What differs is the
installer's prerequisites, checked in containers with `install.sh --check` on 2026-10-30:

| Distro | Python | Sign-in window (WebKitGTK 6) | BlueZ | Notes |
| --- | --- | --- | --- | --- |
| Arch / CachyOS | 3.14 | `python-gobject webkitgtk-6.0` | 5.87 | distro `umu-launcher` package used if installed |
| Fedora 44 | 3.14 | `python3-gobject webkitgtk6.0` | 5.87 | |
| Ubuntu 22.04 | 3.10 | none (sign-in falls back to the web browser) | `bluez` | oldest supported (Python 3.10) |
| Ubuntu 24.04 / 26.04 | 3.12 / 3.14 | `python3-gi gir1.2-webkit-6.0` | 5.72 / 5.85 | AppArmor blocks umu's sandbox: the installer adds `/etc/apparmor.d/zwift-linux-umu` (like Steam's own profile) |
| Debian 13 | 3.13 | `python3-gi gir1.2-webkit-6.0` | 5.82 | |
| openSUSE Tumbleweed | 3.13 | `python3-gobject typelib-1_0-WebKit-6_0` | 5.87 | |

The AppArmor profile is written from the published Ubuntu rules and hasn't been run on a real
Ubuntu machine yet.

## Known limitations

- **Bluetooth reconnect** after a lost link didn't happen once on workout (fenix 7 kept advertising, Zwift scanned for 19 min). Wine does report the device's advertisements again (checked with BlueZ), so the cause is further along (connect/GATT path) and still open. With USB autosuspend off the link hasn't dropped since; ANT+ HR is the fallback.

- **Wine Wayland driver: a hidden window drops to about 1 FPS.** When another window fully covers
  Zwift, GNOME stops sending frame callbacks and the game slows to about 1 FPS. It returns to full
  speed as soon as Zwift is visible again. Keep Zwift uncovered during a ride, or use
  `--display x11` where XWayland works (Mesa GPUs).
- **Ride-highlight recording** can't save clips (Proton's FFmpeg has no MP4 muxer), and Zwift
  retries the encoder several times a second. `zwift` turns it off in `prefs.xml` unless
  `ZWIFT_VIDEO_CAPTURE=1` is set.
- **Hardware video decode** (D3D11) isn't available, so Zwift decodes video in software. On any
  recent CPU this has no visible effect.
- winewayland logs harmless notes about missing optional protocols (text input, clipboard
  control, HDR image descriptions).

## Reporting a new setup

Run `zwift doctor` and include its output, your desktop and version, the GPU and driver version,
and whether `zwift --display x11` and `zwift --display wayland` each show a moving picture and
respond to clicks.

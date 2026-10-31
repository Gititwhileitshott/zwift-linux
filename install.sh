#!/usr/bin/env bash
# Zwift for Linux - installer
#
# Runs the Windows version of Zwift through GE-Proton (via umu-launcher) with
# direct trainer connections:
#   * Bluetooth LE  - built into GE-Proton 11-8+, enabled with PROTON_ENABLE_WINEBTH=1
#   * ANT+ USB      - libusb0.dll bridge shipped in ./ant-libusb (Zwift's ANT driver path -> Linux usbfs)
#
# Works on any x86_64 distro with glibc, Python 3 (3.10+ without a distro umu-launcher), curl and
# BlueZ (Arch/CachyOS/Manjaro, Fedora/Nobara/Bazzite, Debian/Ubuntu/Mint/Pop!_OS, openSUSE, SteamOS
# desktop mode, ...). Nothing is compiled unless you pass --build-starter. Everything goes into your
# home directory; sudo is only used for optional udev rules (ANT+ stick access, Bluetooth adapter
# power saving), an AppArmor profile where Ubuntu needs one, and to start the Bluetooth service.
#
# Usage: ./install.sh [options]      (run ./install.sh --help)
set -euo pipefail

ZL_VERSION="1.1.0"
GE_VER="GE-Proton11-8"
UMU_VER="1.4.4"
UMU_SHA256="eb590691841f7fad3fc3ad8fd5db4ccb87849fe7948e62b28ece7a4ee48cc851"
ZWIFT_SETUP_URL="https://cdn.zwift.com/app/ZwiftSetup.exe"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/zwift-linux"
BIN="$HOME/.local/bin"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
PFX="${ZWIFT_PREFIX:-$HOME/Games/zwift}"
SETUP_EXE=""
DPI="${ZWIFT_DPI:-}"
USE_SUDO=1 DO_BLE=1 DO_ANT=1 ASSUME_YES=0 CHECK_ONLY=0 BUILD_STARTER="${ZWIFT_BUILD_STARTER:-0}"

usage() {
  cat <<EOF
Zwift for Linux installer $ZL_VERSION

  ./install.sh [options]

Options:
  --prefix DIR     Wine prefix for Zwift (default: ~/Games/zwift, or \$ZWIFT_PREFIX)
  --setup FILE     Use this ZwiftSetup.exe instead of downloading it
  --dpi N          Windows DPI for the launcher (96 = 100%, 144 = 150%, 192 = 200%).
                   Default: detected from your desktop scale.
  --no-sudo        Skip the steps that need sudo (udev rules, AppArmor profile, Bluetooth service)
                   and print the commands instead
  --no-ble         Don't enable Bluetooth LE (use Zwift Companion instead)
  --no-ant         Don't install the ANT+ USB bridge
  --build-starter  Build LinuxZwiftLauncher.exe from zwift-start/zwift-start.c instead of using the
                   prebuilt copy (needs the MinGW-w64 cross compiler, x86_64-w64-mingw32-gcc)
  -y, --yes        Accepted for scripts; the installer currently asks no questions
  --check          Only check this PC (distro, Python, sign-in window, Bluetooth, sandbox, display/GPU) and exit
  -h, --help       This help

Re-running the installer updates an existing install and skips finished steps.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PFX="$2"; shift 2 ;;
    --setup) SETUP_EXE="$(realpath "$2")"; shift 2 ;;
    --dpi) DPI="$2"; shift 2 ;;
    --no-sudo) USE_SUDO=0; shift ;;
    --no-ble) DO_BLE=0; shift ;;
    --no-ant) DO_ANT=0; shift ;;
    --build-starter) BUILD_STARTER=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    --check) CHECK_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

c_info=$'\033[1;36m' c_ok=$'\033[1;32m' c_warn=$'\033[1;33m' c_err=$'\033[1;31m' c_off=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$c_info" "$*" "$c_off"; }
ok()   { printf '%s  ok%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '%s  warning:%s %s\n' "$c_warn" "$c_off" "$*" >&2; }
die()  { printf '%sERROR:%s %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }
interactive() { [ "$ASSUME_YES" = 0 ] && [ -t 0 ]; }

# ---------------------------------------------------------------------------------------------
step "Checking your system"
[ "$(uname -m)" = x86_64 ] || die "Zwift for Windows needs an x86_64 PC (found $(uname -m))."
[ "$(id -u)" != 0 ] || die "Run this as your normal user, not root (sudo is requested only where needed)."
for t in curl tar sha256sum sha512sum awk sed grep python3; do
  command -v "$t" >/dev/null || die "Missing required tool: $t"
done
if [ "$CHECK_ONLY" = 0 ] && pgrep -f 'Zwift(App|Launcher)\.exe' >/dev/null 2>&1; then
  die "Zwift is running. Quit it (and its tray icon), then run the installer again."
fi
DISTRO_ID="unknown" DISTRO_LIKE="" DISTRO_NAME="Linux"
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO_ID="${ID:-unknown}" DISTRO_LIKE="${ID_LIKE:-}" DISTRO_NAME="${PRETTY_NAME:-$DISTRO_ID}"
fi
ok "$DISTRO_NAME, kernel $(uname -r)"

pkg_hint() { # pkg_hint <generic package name> -> install command for this distro
  case " $DISTRO_ID $DISTRO_LIKE " in
    *" arch "*|*" cachyos "*|*" manjaro "*|*" endeavouros "*) echo "sudo pacman -S --needed $1" ;;
    *" fedora "*|*" rhel "*|*" nobara "*|*" bazzite "*) echo "sudo dnf install $1" ;;
    *" debian "*|*" ubuntu "*) echo "sudo apt install $1" ;;
    *" opensuse"*|*" suse "*) echo "sudo zypper install $1" ;;
    *" steamos "*) echo "(SteamOS) $1 is preinstalled" ;;
    *) echo "install the '$1' package with your package manager" ;;
  esac
}

# Ubuntu 23.10+ (AppArmor) lets unprivileged programs create user namespaces only with a profile that
# allows it. umu's Steam Linux Runtime container (pressure-vessel / bwrap) needs one, like Steam's own.
APPARMOR_FILE=/etc/apparmor.d/zwift-linux-umu
APPARMOR_PROFILE='abi <abi/4.0>,
include <tunables/global>
profile zwift-linux-umu @{HOME}/.local/share/umu/**/srt-bwrap flags=(unconfined) {
  userns,
  include if exists <local/zwift-linux-umu>
}'
userns_restricted() { [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)" = 1 ]; }

if [ "$CHECK_ONLY" = 1 ]; then
  step "Prerequisites"
  if command -v umu-run >/dev/null; then ok "umu-launcher from your distro: $(command -v umu-run)"
  elif python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then ok "$(python3 -V) (umu-launcher zipapp will be downloaded)"
  else warn "no umu-launcher and no Python 3.10+: $(pkg_hint python3)"; fi
  if python3 -c 'import gi; gi.require_version("Gtk", "4.0"); gi.require_version("WebKit", "6.0"); from gi.repository import Gtk, WebKit' 2>/dev/null; then
    ok "WebKitGTK 6: Zwift sign-in opens in its own window"
  else
    note_pkg="python3-gobject + webkitgtk-6.0"
    case " $DISTRO_ID $DISTRO_LIKE " in
      *" debian "*|*" ubuntu "*) note_pkg="python3-gi gir1.2-webkit-6.0" ;;
      *" fedora "*|*" rhel "*) note_pkg="python3-gobject webkitgtk6.0" ;;
      *" arch "*|*" cachyos "*|*" manjaro "*|*" endeavouros "*) note_pkg="python-gobject webkitgtk-6.0" ;;
      *" opensuse"*|*" suse "*) note_pkg="python3-gobject typelib-1_0-WebKit-6_0" ;;
    esac
    warn "no WebKitGTK 6 for Python: sign-in will use your web browser instead (optional: $(pkg_hint "$note_pkg"))"
  fi
  if command -v bluetoothctl >/dev/null; then ok "BlueZ $(bluetoothctl --version 2>/dev/null | awk '{print $2}')"
  else warn "BlueZ not found, needed for Bluetooth sensors: $(pkg_hint bluez)"; fi
  if userns_restricted; then
    if [ -f "$APPARMOR_FILE" ]; then ok "AppArmor user-namespace profile for umu present"
    else warn "AppArmor restricts user namespaces; install.sh will add $APPARMOR_FILE (sudo) so umu's container can start"; fi
  elif command -v unshare >/dev/null && ! unshare -Ur true 2>/dev/null; then
    warn "unprivileged user namespaces are disabled; umu's container (and Steam's) can't start"
  else ok "user namespaces available (umu container)"; fi
  # shellcheck source=/dev/null
  DATA="$DATA" . "$HERE/share/zwift-display.sh"
  zl_pick_display
  ok "$(zl_session) session, GPU driver $(zl_gpu_driver)$( [ -n "$(zl_nvidia_major)" ] && echo " $(cat /sys/module/nvidia/version)"): Wine $ZL_DISPLAY driver ($ZL_DISPLAY_WHY)"
  exit 0
fi

# ---------------------------------------------------------------------------------------------
step "1/7 umu-launcher (runs Proton outside Steam)"
mkdir -p "$DATA"
if command -v umu-run >/dev/null; then
  UMU="$(command -v umu-run)"
  ok "using your distro's umu-launcher: $UMU"
else
  UMU="$DATA/umu/umu-run"
  if [ ! -x "$UMU" ] || [ "$(cat "$DATA/umu/.version" 2>/dev/null)" != "$UMU_VER" ]; then
    command -v python3 >/dev/null || die "Python 3 is needed for umu-launcher: $(pkg_hint python3)"
    python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' \
      || die "umu-launcher needs Python 3.10 or newer (found $(python3 -V 2>&1))"
    tmp="$(mktemp -d)"
    curl -fL --progress-bar -o "$tmp/umu.tar" \
      "https://github.com/Open-Wine-Components/umu-launcher/releases/download/$UMU_VER/umu-launcher-$UMU_VER-zipapp.tar"
    echo "$UMU_SHA256  $tmp/umu.tar" | sha256sum -c --quiet - || die "umu-launcher download failed its checksum"
    rm -rf "$DATA/umu" && tar -xf "$tmp/umu.tar" -C "$DATA" && rm -rf "$tmp"
    echo "$UMU_VER" > "$DATA/umu/.version"
  fi
  ok "umu-launcher $UMU_VER (zipapp) in $DATA/umu"
fi

# ---------------------------------------------------------------------------------------------
step "2/7 $GE_VER (Proton with Bluetooth LE support)"
GE="$DATA/$GE_VER-x86_64"
if [ ! -x "$GE/proton" ]; then
  base="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$GE_VER"
  tmp="$(mktemp -d -p "$DATA")"
  curl -fL --progress-bar -o "$tmp/$GE_VER-x86_64.tar.gz" "$base/$GE_VER-x86_64.tar.gz"
  curl -fsSL -o "$tmp/$GE_VER-x86_64.sha512sum" "$base/$GE_VER-x86_64.sha512sum"
  (cd "$tmp" && sha512sum -c --quiet "$GE_VER-x86_64.sha512sum") || die "$GE_VER download failed its checksum"
  tar -xzf "$tmp/$GE_VER-x86_64.tar.gz" -C "$DATA" && rm -rf "$tmp"
  [ -x "$GE/proton" ] || die "unexpected $GE_VER archive layout"
fi
grep -q PROTON_ENABLE_WINEBTH "$GE/proton" || warn "$GE_VER has no PROTON_ENABLE_WINEBTH switch; Bluetooth LE will not work"
ok "$(awk '{print $2}' "$GE/version" 2>/dev/null || echo "$GE_VER") in $GE"

# ---------------------------------------------------------------------------------------------
step "3/7 ANT+ USB bridge"
if [ "$DO_ANT" = 1 ]; then
  for f in x86_64-windows/libusb0.dll x86_64-unix/libusb0.so placeholder/libusb0.dll; do
    [ -f "$HERE/ant-libusb/build/$f" ] || die "missing $HERE/ant-libusb/build/$f (incomplete package?)"
  done
  install -m 644 "$HERE/ant-libusb/build/x86_64-windows/libusb0.dll" "$GE/files/lib/wine/x86_64-windows/libusb0.dll"
  install -m 755 "$HERE/ant-libusb/build/x86_64-unix/libusb0.so"     "$GE/files/lib/wine/x86_64-unix/libusb0.so"
  install -Dm 644 "$HERE/ant-libusb/build/placeholder/libusb0.dll"   "$DATA/libusb0-placeholder.dll"
  install -Dm 644 "$HERE/ant-libusb/test/antprobe.exe"               "$DATA/antprobe.exe"
  ok "libusb0.dll bridge installed into $GE_VER"
else
  ok "skipped (--no-ant)"
fi

# ---------------------------------------------------------------------------------------------
step "4/7 System setup (USB permission for ANT+ sticks, Bluetooth service)"
UDEV_RULE='SUBSYSTEM=="usb", ATTRS{idVendor}=="0fcf", ATTRS{idProduct}=="1008|1009", MODE="0666", TAG+="uaccess"'
UDEV_FILE=/etc/udev/rules.d/51-zwift-ant-usb.rules
manual=()
if [ "$DO_ANT" = 1 ] && [ "$(cat "$UDEV_FILE" 2>/dev/null)" != "$UDEV_RULE" ]; then
  if [ "$USE_SUDO" = 1 ] && command -v sudo >/dev/null; then
    echo "  Adding $UDEV_FILE so your user can use ANT+ USB sticks (sudo):"
    if echo "$UDEV_RULE" | sudo tee "$UDEV_FILE" >/dev/null; then
      sudo udevadm control --reload-rules || true
      sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=0fcf || true
      ok "udev rule installed"
    else
      warn "could not write $UDEV_FILE"; manual+=("echo '$UDEV_RULE' | sudo tee $UDEV_FILE && sudo udevadm control --reload-rules && sudo udevadm trigger")
    fi
  else
    manual+=("echo '$UDEV_RULE' | sudo tee $UDEV_FILE && sudo udevadm control --reload-rules && sudo udevadm trigger")
  fi
elif [ "$DO_ANT" = 1 ]; then ok "udev rule already present"; fi

if userns_restricted && [ "$(cat "$APPARMOR_FILE" 2>/dev/null)" != "$APPARMOR_PROFILE" ]; then
  if [ "$USE_SUDO" = 1 ] && command -v sudo >/dev/null; then
    echo "  Adding $APPARMOR_FILE so umu's container may use user namespaces (sudo):"
    if printf '%s\n' "$APPARMOR_PROFILE" | sudo tee "$APPARMOR_FILE" >/dev/null && sudo apparmor_parser -r "$APPARMOR_FILE"; then
      ok "AppArmor profile installed"
    else warn "could not load $APPARMOR_FILE; umu may fail with 'bwrap: setting up uid map: Permission denied'"; fi
  else
    manual+=("printf '%s\\n' '$APPARMOR_PROFILE' | sudo tee $APPARMOR_FILE && sudo apparmor_parser -r $APPARMOR_FILE")
  fi
fi

# USB autosuspend on Bluetooth adapters (btusb enable_autosuspend=Y on most distros) can make the controller
# drop BLE links mid-ride ("ACL packet for unknown connection handle" in dmesg); keep USB adapters awake.
BT_RULE='ACTION=="bind", SUBSYSTEM=="usb", DRIVER=="btusb", RUN+="/bin/sh -c '"'"'echo on > /sys%p/../power/control'"'"'"'
BT_RULE_FILE=/etc/udev/rules.d/52-zwift-bluetooth-awake.rules
if [ "$DO_BLE" = 1 ] && [ "$(cat "$BT_RULE_FILE" 2>/dev/null)" != "$BT_RULE" ]; then
  if [ "$USE_SUDO" = 1 ] && command -v sudo >/dev/null; then
    echo "  Adding $BT_RULE_FILE to turn off USB power saving for Bluetooth adapters (sudo):"
    if echo "$BT_RULE" | sudo tee "$BT_RULE_FILE" >/dev/null; then
      sudo udevadm control --reload-rules || true
      for d in /sys/class/bluetooth/hci*/device/..; do   # apply now, without replugging
        [ -f "$d/power/control" ] && echo on | sudo tee "$d/power/control" >/dev/null
      done
      ok "Bluetooth adapter kept awake"
    else warn "could not write $BT_RULE_FILE"; fi
  else
    manual+=("sudo tee $BT_RULE_FILE <<'RULE'
$BT_RULE
RULE
sudo udevadm control --reload-rules")
  fi
fi

if [ "$DO_BLE" = 1 ]; then
  if ! command -v bluetoothctl >/dev/null && ! systemctl list-unit-files bluetooth.service >/dev/null 2>&1; then
    warn "BlueZ (the Linux Bluetooth stack) was not found: $(pkg_hint bluez)"
  elif command -v systemctl >/dev/null && ! systemctl is-active --quiet bluetooth 2>/dev/null; then
    if [ "$USE_SUDO" = 1 ] && command -v sudo >/dev/null; then
      sudo systemctl enable --now bluetooth && ok "Bluetooth service started" || warn "could not start bluetooth.service"
    else
      manual+=("sudo systemctl enable --now bluetooth")
    fi
  else
    ok "Bluetooth service is running"
  fi
fi

# ---------------------------------------------------------------------------------------------
step "5/7 Wine prefix $PFX (first run installs .NET 4.8, fonts and WebView2 - this takes a while)"
export WINEPREFIX="$PFX" PROTONPATH="$GE" GAMEID="umu-zwift" PROTON_VERB=waitforexitandrun
export PROTON_USE_XALIA=0 WINEDLLOVERRIDES="libusb0=b;vccorlib140=n,b;winemenubuilder.exe=d"
mkdir -p "$PFX"

# Installs made with older scripts linked Bluetooth modules from an older GE-Proton into the prefix:
# point those links at the current runner and drop the old runner.
for old in "$DATA"/GE-Proton*-x86_64; do
  [ -d "$old" ] && [ "$old" != "$GE" ] || continue
  while IFS= read -r -d '' link; do
    tgt="$(readlink "$link")"; rel="${tgt#"$old"/}"
    if [ -e "$GE/$rel" ]; then ln -sfn "$GE/$rel" "$link"; else rm -f "$link"; fi
  done < <(find "$PFX/drive_c/windows" -maxdepth 3 -type l -lname "$old/*" -print0 2>/dev/null)
  echo "  removing old runner $(basename "$old")"; rm -rf "$old"
done

# The umu-zwift protonfix (part of GE-Proton) installs corefonts, dotnet48, d3dcompiler_47 and
# webview2 the first time anything runs with GAMEID=umu-zwift.
if [ ! -f "$PFX/.zwift-linux" ] && [ ! -f "$PFX/.zwift-linux-deps" ]; then
  echo "  (a 'rundll32.exe - This application could not be started' box may appear: click No)"
  "$UMU" wineboot -u || warn "prefix setup returned an error"
  [ -d "$PFX/drive_c/windows/system32" ] || die "umu-launcher could not create the prefix. It needs internet access to repo.steampowered.com on first run (it downloads the Steam Linux Runtime); see the messages above."
  echo "$ZL_VERSION" > "$PFX/.zwift-linux"
fi
ok "prefix ready"

detect_dpi() {
  local s="" d=""
  if command -v kscreen-doctor >/dev/null; then              # KDE Plasma
    s="$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -o 'Scale: *[0-9.]*' | head -1 | awk '{print $2}')"
  fi
  if [ -z "$s" ] && command -v xrdb >/dev/null && [ -n "${DISPLAY:-}" ]; then   # X11 / XWayland Xft.dpi
    d="$(xrdb -query 2>/dev/null | awk '/^Xft.dpi:/{print int($2); exit}')"
  fi
  if [ -z "$s" ] && [ -z "$d" ] && command -v gsettings >/dev/null; then       # GNOME integer scaling
    s="$(gsettings get org.gnome.desktop.interface scaling-factor 2>/dev/null | awk '{print $2}')"
    [ "$s" = 0 ] && s=""
  fi
  [ -n "$s" ] && d="$(awk -v s="$s" 'BEGIN{printf "%d", 96*s+0.5}')"
  echo "$d"
}
[ -n "$DPI" ] || DPI="$(detect_dpi)"
if [[ "$DPI" =~ ^[0-9]+$ ]] && [ "$DPI" -ge 96 ] && [ "$DPI" -le 480 ]; then
  "$UMU" reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d "$DPI" /f >/dev/null 2>&1 \
    && ok "Windows DPI set to $DPI ($((DPI * 100 / 96))%)" || warn "could not set DPI"
else
  echo "  DPI not detected; if the launcher looks tiny, re-run with --dpi 144 (150%) or --dpi 192 (200%)"
fi
# Without these, .NET offers only SSL3/TLS 1.0 and Zwift's servers refuse the launcher's HTTPS calls
# ("Could not create SSL/TLS secure channel"). Set in both the 64-bit and 32-bit registry views.
tls_ok=1
for k in 'HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' 'HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319'; do
  for v in SchUseStrongCrypto SystemDefaultTlsVersions; do
    "$UMU" reg add "$k" /v "$v" /t REG_DWORD /d 1 /f >/dev/null 2>&1 || tls_ok=0
  done
done
[ "$tls_ok" = 1 ] && ok ".NET allowed to use TLS 1.2+" || warn "could not set the .NET TLS registry keys"
[ "$DO_ANT" = 1 ] && install -Dm 644 "$DATA/libusb0-placeholder.dll" "$PFX/drive_c/windows/system32/libusb0.dll"

# ---------------------------------------------------------------------------------------------
step "6/7 Zwift"
ZDIR="$PFX/drive_c/Program Files (x86)/Zwift"
if [ -f "$ZDIR/ZwiftLauncher.exe" ]; then
  ok "Zwift launcher already installed"
else
  if [ -z "$SETUP_EXE" ]; then
    for c in "$HERE/ZwiftSetup.exe" "$HOME/Downloads/ZwiftSetup.exe"; do [ -f "$c" ] && SETUP_EXE="$c" && break; done
  fi
  if [ -z "$SETUP_EXE" ]; then
    SETUP_EXE="$DATA/ZwiftSetup.exe"
    curl -fL --progress-bar -o "$SETUP_EXE" "$ZWIFT_SETUP_URL" \
      || die "could not download ZwiftSetup.exe - download it from zwift.com and pass --setup FILE"
  fi
  echo "  Installing the Zwift launcher from $SETUP_EXE"
  ( "$UMU" "$SETUP_EXE" /SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL >"$DATA/install-zwift.log" 2>&1 ) &
  UMU_PID=$!
  # The installer starts the WebView2 launcher when it's done; zwift doesn't need it, so stop the prefix
  # once the launcher files are in place and fetch the game directly instead.
  for _ in $(seq 1 360); do
    [ -f "$ZDIR/ZwiftLauncher.exe" ] && { sleep 15; break; }
    kill -0 "$UMU_PID" 2>/dev/null || break
    sleep 5
  done
  "$GE/files/bin/wineserver" -k 2>/dev/null || true
  wait "$UMU_PID" 2>/dev/null || true
  [ -f "$ZDIR/ZwiftLauncher.exe" ] || die "Zwift did not install - see $DATA/install-zwift.log"
  ok "Zwift launcher installed"
fi
echo "  Downloading or updating the game from Zwift's servers (about 5 GB the first time)"
python3 "$HERE/share/zwift-fetch-game.py" "$ZDIR" --if-outdated \
  && ok "Zwift game files up to date" || die "game download failed - re-run install.sh to resume"
# Zwift's installer copies the Windows libusb0.dll (needs a kernel driver Wine can't load); keep the bridge.
[ "$DO_ANT" = 1 ] && install -Dm 644 "$DATA/libusb0-placeholder.dll" "$PFX/drive_c/windows/system32/libusb0.dll"

# ---------------------------------------------------------------------------------------------
step "7/7 'zwift' command and app menu entry"
mkdir -p "$BIN" "$APPS"
# leftovers from the earlier zwift-setup.sh
grep -qs 'Windows build via GE-Proton' "$APPS/zwift.desktop" && rm -f "$APPS/zwift.desktop"
rm -rf "$DATA/ble-patch"
[ -f "$BIN/zwift" ] && [ ! -L "$BIN/zwift" ] && grep -qs 'generated by zwift-setup.sh' "$BIN/zwift" && rm -f "$BIN/zwift"
install -m 755 "$HERE/share/zwift-launcher.sh" "$DATA/zwift-launcher.sh"
install -m 755 "$HERE/share/zwift-doctor.sh" "$DATA/zwift-doctor.sh"
install -m 644 "$HERE/share/zwift-display.sh" "$DATA/zwift-display.sh"
install -m 755 "$HERE/share/zwift-fetch-game.py" "$DATA/zwift-fetch-game.py"
install -m 755 "$HERE/share/zwift-auth.py" "$DATA/zwift-auth.py"
# The game starter: prebuilt by default, or built here from its source with --build-starter.
if [ "$BUILD_STARTER" = 1 ]; then
  if ! command -v x86_64-w64-mingw32-gcc >/dev/null; then
    case " $DISTRO_ID $DISTRO_LIKE " in
      *" arch "*|*" cachyos "*|*" manjaro "*|*" endeavouros "*) mingw_pkg="mingw-w64-gcc" ;;
      *" fedora "*|*" rhel "*|*" nobara "*|*" bazzite "*) mingw_pkg="mingw64-gcc" ;;
      *" debian "*|*" ubuntu "*) mingw_pkg="gcc-mingw-w64-x86-64" ;;
      *" opensuse"*|*" suse "*) mingw_pkg="mingw64-cross-gcc" ;;
      *) mingw_pkg="mingw-w64 (x86_64 cross compiler)" ;;
    esac
    die "--build-starter needs x86_64-w64-mingw32-gcc: $(pkg_hint "$mingw_pkg")"
  fi
  x86_64-w64-mingw32-gcc -municode -O2 -s -Wl,--subsystem,windows \
    -o "$DATA/LinuxZwiftLauncher.exe" "$HERE/zwift-start/zwift-start.c" || die "building LinuxZwiftLauncher.exe failed"
  ok "LinuxZwiftLauncher.exe built from zwift-start/zwift-start.c"
else
  (cd "$HERE/zwift-start" && sha256sum -c --quiet SHA256SUMS) || die "zwift-start/LinuxZwiftLauncher.exe doesn't match SHA256SUMS (use --build-starter to build it from source)"
  install -m 644 "$HERE/zwift-start/LinuxZwiftLauncher.exe" "$DATA/LinuxZwiftLauncher.exe"
  ok "LinuxZwiftLauncher.exe (prebuilt, sha256 $(sha256sum "$DATA/LinuxZwiftLauncher.exe" | cut -c1-16)...; --build-starter builds it from source)"
fi
rm -f "$DATA/zwift-start.exe"   # old name; ZwiftApp only accepts a parent whose path contains ZwiftLauncher.exe
cat > "$DATA/zwift.conf" <<EOF
# written by zwift-linux $ZL_VERSION installer - re-run install.sh to change
ZL_VERSION="$ZL_VERSION"
UMU="$UMU"
GE="$GE"
PFX="$PFX"
DO_BLE=$DO_BLE
DO_ANT=$DO_ANT
DPI="$DPI"
EOF
ln -sfn "$DATA/zwift-launcher.sh" "$BIN/zwift"
icon="applications-games"
[ -f "$HERE/share/zwift-linux.svg" ] && install -Dm 644 "$HERE/share/zwift-linux.svg" "$DATA/zwift-linux.svg" && icon="$DATA/zwift-linux.svg"
cat > "$APPS/zwift-linux.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Zwift
Comment=Zwift (Windows version via GE-Proton) with Bluetooth and ANT+ trainers
Exec=$BIN/zwift
Icon=$icon
Terminal=false
Categories=Game;Sports;
StartupWMClass=zwiftapp.exe
EOF
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null || true
ok "installed: zwift (in $BIN), 'Zwift' in your app menu"

echo
printf '%sZwift is ready.%s\n' "$c_ok" "$c_off"
echo "  Start it:        zwift            (or 'Zwift' in your app menu)"
echo "  Check hardware:  zwift doctor"
echo "  Uninstall:       $HERE/uninstall.sh"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "  Note: $BIN is not on your PATH; use $BIN/zwift or add it to PATH." ;; esac
[ -d "$HOME/.cache/ge-proton-ble" ] && echo "  Tip: the old Bluetooth patch build cache is no longer needed: rm -rf ~/.cache/ge-proton-ble (about 1.5 GB)"
if [ ${#manual[@]} -gt 0 ]; then
  echo
  warn "run these yourself to finish the system setup:"
  for m in "${manual[@]}"; do echo "    $m"; done
fi

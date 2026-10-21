#!/usr/bin/env bash
# Zwift for Linux - installer
#
# Runs the Windows version of Zwift through GE-Proton (via umu-launcher) with
# direct trainer connections:
#   * Bluetooth LE  - built into GE-Proton 11-8+, enabled with PROTON_ENABLE_WINEBTH=1
#   * ANT+ USB      - libusb0.dll bridge shipped in ./ant-libusb (Zwift's ANT driver path -> Linux usbfs)
#
# Works on any x86_64 distro with glibc, Python 3.10+, curl and BlueZ (Arch/CachyOS/Manjaro,
# Fedora/Nobara/Bazzite, Debian/Ubuntu/Mint/Pop!_OS, openSUSE, SteamOS desktop mode, ...).
# Nothing is compiled. Everything goes into your home directory; sudo is only used for an
# optional udev rule (ANT+ stick access) and to start the Bluetooth service.
#
# Usage: ./install.sh [options]      (run ./install.sh --help)
set -euo pipefail

ZL_VERSION="1.0.2"
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
USE_SUDO=1 DO_BLE=1 DO_ANT=1 ASSUME_YES=0

usage() {
  cat <<EOF
Zwift for Linux installer $ZL_VERSION

  ./install.sh [options]

Options:
  --prefix DIR     Wine prefix for Zwift (default: ~/Games/zwift, or \$ZWIFT_PREFIX)
  --setup FILE     Use this ZwiftSetup.exe instead of downloading it
  --dpi N          Windows DPI for the launcher (96 = 100%, 144 = 150%, 192 = 200%).
                   Default: detected from your desktop scale.
  --no-sudo        Skip the udev rule and Bluetooth service steps (prints them instead)
  --no-ble         Don't enable Bluetooth LE (use Zwift Companion instead)
  --no-ant         Don't install the ANT+ USB bridge
  -y, --yes        Don't ask questions (the game download is waited for automatically)
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
    -y|--yes) ASSUME_YES=1; shift ;;
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
for t in curl tar sha256sum sha512sum awk sed grep; do
  command -v "$t" >/dev/null || die "Missing required tool: $t"
done
if pgrep -f 'Zwift(App|Launcher)\.exe' >/dev/null 2>&1; then
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
[ "$DO_ANT" = 1 ] && install -Dm 644 "$DATA/libusb0-placeholder.dll" "$PFX/drive_c/windows/system32/libusb0.dll"

# ---------------------------------------------------------------------------------------------
step "6/7 Zwift"
ZDIR="$PFX/drive_c/Program Files (x86)/Zwift"
if [ -f "$ZDIR/ZwiftApp.exe" ]; then
  ok "already installed (Zwift updates itself from the launcher)"
else
  if [ -z "$SETUP_EXE" ]; then
    for c in "$HERE/ZwiftSetup.exe" "$HOME/Downloads/ZwiftSetup.exe"; do [ -f "$c" ] && SETUP_EXE="$c" && break; done
  fi
  if [ -z "$SETUP_EXE" ]; then
    SETUP_EXE="$DATA/ZwiftSetup.exe"
    curl -fL --progress-bar -o "$SETUP_EXE" "$ZWIFT_SETUP_URL" \
      || die "could not download ZwiftSetup.exe - download it from zwift.com and pass --setup FILE"
  fi
  echo "  Installing from $SETUP_EXE"
  echo "  The Zwift launcher will open and download the game (about 2 GB)."
  ( "$UMU" "$SETUP_EXE" /SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL >"$DATA/install-zwift.log" 2>&1 ) &
  UMU_PID=$!
  if interactive; then
    read -r -p "  >>> When the download has finished, close the Zwift launcher and press Enter... " _ </dev/tty
  else
    echo "  waiting for the game download to finish..."
    for _ in $(seq 1 720); do
      [ -f "$ZDIR/ZwiftApp.exe" ] && { sleep 60; break; }
      kill -0 "$UMU_PID" 2>/dev/null || break
      sleep 5
    done
  fi
  "$GE/files/bin/wineserver" -k 2>/dev/null || true
  wait "$UMU_PID" 2>/dev/null || true
  [ -f "$ZDIR/ZwiftLauncher.exe" ] || die "Zwift did not install - see $DATA/install-zwift.log"
  [ -f "$ZDIR/ZwiftApp.exe" ] && ok "Zwift installed" || warn "game files not downloaded yet; the first start will download them"
fi
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

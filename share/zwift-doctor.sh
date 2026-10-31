#!/usr/bin/env bash
# zwift doctor - checks the pieces Zwift needs for direct trainer connections on Linux.
set -u
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
DATA="$(dirname "$SELF")"
# shellcheck source=/dev/null
. "$DATA/zwift.conf"
G=$'\033[1;32m' Y=$'\033[1;33m' R=$'\033[1;31m' O=$'\033[0m'
pass() { printf '  %sOK%s    %s\n' "$G" "$O" "$*"; }
note() { printf '  %sNOTE%s  %s\n' "$Y" "$O" "$*"; }
fail() { printf '  %sFAIL%s  %s\n' "$R" "$O" "$*"; }
ZDIR="$PFX/drive_c/Program Files (x86)/Zwift"

echo "zwift-linux ${ZL_VERSION:-?} - $( (. /etc/os-release; echo "${PRETTY_NAME:-Linux}") 2>/dev/null), kernel $(uname -r)"

echo "Install"
[ -x "$GE/proton" ] && pass "runner $(awk '{print $2}' "$GE/version" 2>/dev/null)" || fail "runner missing: $GE"
[ -x "$UMU" ] && pass "umu-launcher $UMU" || fail "umu-launcher missing: $UMU"
if [ -f "$ZDIR/ZwiftApp.exe" ]; then
  v="$(ls "$ZDIR"/Zwift_ver_cur.*.xml 2>/dev/null | sed 's/.*Zwift_ver_cur\.\([0-9]*\)\.xml/\1/' | head -1)"
  pass "Zwift installed (build ${v:-?}) in $PFX"
else fail "Zwift not installed in $PFX"; fi
dpi="$(grep -A40 '^\[Control Panel\\\\Desktop\]' "$PFX/user.reg" 2>/dev/null | grep -m1 '"LogPixels"' | sed 's/.*dword://')"
[ -n "$dpi" ] && pass "Windows DPI $((16#$dpi)) (re-run install.sh --dpi N to change)"

echo "Sign-in (zwift-auth.py)"
webkit_hint() { # distro packages for PyGObject + GTK 4 + WebKitGTK 6.0
  local id like; id="$( (. /etc/os-release; echo "${ID:-}") 2>/dev/null)"; like="$( (. /etc/os-release; echo "${ID_LIKE:-}") 2>/dev/null)"
  case " $id $like " in
    *" arch "*) echo "sudo pacman -S --needed python-gobject gtk4 webkitgtk-6.0" ;;
    *" fedora "*|*" rhel "*) echo "sudo dnf install python3-gobject gtk4 webkitgtk6.0" ;;
    *" debian "*|*" ubuntu "*) echo "sudo apt install python3-gi gir1.2-gtk-4.0 gir1.2-webkit-6.0" ;;
    *" opensuse"*|*" suse "*) echo "sudo zypper install python3-gobject typelib-1_0-Gtk-4_0 typelib-1_0-WebKit-6_0" ;;
    *) echo "install PyGObject with GTK 4 and WebKitGTK 6.0 from your package manager" ;;
  esac
}
if ! command -v python3 >/dev/null; then fail "python3 not found - needed to sign in to Zwift"
elif python3 -c 'import gi; gi.require_version("Gtk","4.0"); gi.require_version("WebKit","6.0"); from gi.repository import Gtk, WebKit' 2>/dev/null; then
  pass "sign-in window available (GTK 4 + WebKitGTK 6.0)"
else
  note "no GTK 4 / WebKitGTK 6.0 for Python: sign-in opens in your web browser instead. For the built-in window: $(webkit_hint)"
fi
[ -f "$DATA/zwift-auth.py" ] && python3 "$DATA/zwift-auth.py" status 2>&1 | sed 's/^/          /'

echo "Display"
# shellcheck source=/dev/null
. "$DATA/zwift-display.sh"
zl_pick_display
gl="$(command -v glxinfo >/dev/null && glxinfo -B 2>/dev/null | sed -n 's/^OpenGL renderer string: //p')"
pass "$(zl_session) session, GPU driver $(zl_gpu_driver)${gl:+ ($gl)}$( [ -n "$(zl_nvidia_major)" ] && echo ", NVIDIA $(cat /sys/module/nvidia/version)")"
pass "Zwift will use Wine's $ZL_DISPLAY driver: $ZL_DISPLAY_WHY"
[ -s "$DATA/display.auto" ] && note "automatic fallback active ($DATA/display.auto); delete it to retry the default"
note "if the Zwift window freezes or stays black, try: zwift --display $( [ "$ZL_DISPLAY" = wayland ] && echo x11 || echo wayland)"

echo "Bluetooth LE"
if [ "$DO_BLE" != 1 ]; then note "disabled at install (--no-ble)"
else
  grep -q PROTON_ENABLE_WINEBTH "$GE/proton" && pass "runner supports PROTON_ENABLE_WINEBTH" || fail "runner lacks Bluetooth LE support"
  if command -v bluetoothctl >/dev/null; then
    show="$(timeout 5 bluetoothctl show 2>/dev/null)"
    if [ -z "$show" ]; then fail "no Bluetooth adapter found (or bluetooth.service not running)"
    else
      echo "$show" | grep -q 'Powered: yes' && pass "adapter $(echo "$show" | awk '/^Controller/{print $2; exit}') is powered on" \
        || fail "adapter is off: bluetoothctl power on"
      if ! pgrep -f 'ZwiftApp\.exe' >/dev/null; then
        if timeout 10 bluetoothctl --timeout 3 scan on 2>&1 | grep -qE 'InProgress|Failed to start discovery'; then
          fail "the adapter refuses to scan (org.bluez.Error.InProgress) - 'zwift' resets it at start, or run: bluetoothctl power off; bluetoothctl power on"
        else
          pass "Bluetooth scanning works"
        fi
      fi
    fi
    # USB autosuspend on the adapter can drop BLE links (supervision timeout) mid-ride
    bt="$(readlink -f /sys/class/bluetooth/hci0/device/.. 2>/dev/null)"
    if [ -n "$bt" ] && [ -f "$bt/power/control" ]; then
      if [ "$(cat "$bt/power/control")" = auto ]; then
        note "USB power saving (autosuspend) is on for the Bluetooth adapter; sensors may drop mid-ride - re-run install.sh to turn it off"
      else pass "USB power saving is off for the Bluetooth adapter"; fi
    fi
    if ! pgrep -f 'ZwiftApp\.exe' >/dev/null; then
      for mac in $(grep -oiE '_ORG_BLUEZ_HCI[0-9]+&[0-9A-F]{12}' "$PFX/system.reg" 2>/dev/null | grep -oiE '[0-9A-F]{12}$' | tr 'a-f' 'A-F' | sort -u | sed 's/../&:/g; s/:$//'); do
        timeout 5 bluetoothctl info "$mac" 2>/dev/null | grep -q 'Connected: yes' \
          && note "$mac ($(timeout 5 bluetoothctl info "$mac" | awk -F': ' '/Name:/{print $2; exit}')) is still connected to this PC with Zwift closed - 'zwift' releases it at start"
      done
    fi
  else fail "bluetoothctl not found - install BlueZ"; fi
fi

echo "ANT+ USB"
if [ "$DO_ANT" != 1 ]; then note "disabled at install (--no-ant)"
else
  [ -f "$GE/files/lib/wine/x86_64-unix/libusb0.so" ] && pass "libusb0 bridge installed in runner" || fail "libusb0 bridge missing from runner - re-run install.sh"
  stick=""
  for d in /sys/bus/usb/devices/*; do
    [ "$(cat "$d/idVendor" 2>/dev/null)" = 0fcf ] || continue
    stick="$d"; pid="$(cat "$d/idProduct")"
    node="$(printf '/dev/bus/usb/%03d/%03d' "$(cat "$d/busnum")" "$(cat "$d/devnum")")"
    pass "found $(cat "$d/product" 2>/dev/null || echo ANT stick) (0fcf:$pid)"
    case "$pid" in 1008|1009) ;; *) note "0fcf:$pid is not an ANT USB-2/USB-m stick; Zwift may not use it" ;; esac
    [ -w "$node" ] && pass "$node is writable" || fail "$node not writable - re-run install.sh (udev rule) and replug the stick"
  done
  [ -n "$stick" ] || note "no ANT+ USB stick plugged in"
  if [ -n "$stick" ] && [ -f "$DATA/antprobe.exe" ]; then
    if pgrep -f 'ZwiftApp\.exe' >/dev/null; then note "Zwift is running; skipping the live stick test"
    else
      echo "  running a live test through Wine (reset, capabilities, assign channel)..."
      export WINEPREFIX="$PFX" PROTONPATH="$GE" GAMEID="umu-zwift" PROTON_USE_XALIA=0 WINEDLLOVERRIDES="libusb0=b"
      cp -f "$DATA/libusb0-placeholder.dll" "$PFX/drive_c/windows/system32/libusb0.dll" 2>/dev/null
      out="$("$UMU" "$DATA/antprobe.exe" 2>/dev/null | tr -d '\r')"
      echo "$out" | grep -qE "^OK: async receive" && pass "ANT+ stick works through Wine (Zwift's access pattern)" \
        || { fail "live ANT+ test failed:"; echo "$out" | grep -E "^(OK|FAIL|WARN|INFO)" | sed 's/^/          /'; }
    fi
  fi
fi

echo "Last Zwift session"
L="$(ls -t "$PFX"/drive_c/users/*/AppData/Local/Zwift/Logs/Log.txt 2>/dev/null | head -1)"
if [ -n "$L" ]; then
  head -2 "$L" | sed 's/^/          /'
  grep -q 'ANT USB receiver found' "$L" && pass "Zwift found the ANT+ stick" || note "Zwift did not report an ANT+ stick"
  grep -q 'Bluetooth Radio is On' "$L" && pass "Zwift found the Bluetooth radio" || note "Zwift did not report a Bluetooth radio"
  grep -E '^\[[0-9:]+\] +(Power|Cadence|HR|Controllable Trainer|Speed|Steering): ' "$L" | sed 's/^\[[0-9:]*\] *//' | sort -u | sed 's/^/          paired  /'
else note "no Zwift log yet - start Zwift once"; fi
echo "Run log: $DATA/last-run.log"

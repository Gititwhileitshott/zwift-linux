#!/usr/bin/env bash
# ANT+ dongle test for Zwift-under-Wine.
# Checks the dongle on Linux, fixes USB permissions (asks for sudo once), then runs a
# 64-bit Windows test program through Wine using the libusb0.dll bridge. Output is
# also saved to ant-test-output.txt next to this script.
set -u
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$KIT/ant-test-output.txt"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/zwift-linux"
exec > >(tee "$OUT") 2>&1
echo "== ANT+ test $(date -Is) on $(uname -sr), $(. /etc/os-release; echo "$PRETTY_NAME")"

# 1. find the stick
DEV=""
for d in /sys/bus/usb/devices/*; do
  [ -f "$d/idVendor" ] || continue
  if [ "$(cat "$d/idVendor")" = "0fcf" ]; then
    pid=$(cat "$d/idProduct"); DEV="$d"
    printf 'Found 0fcf:%s  %s %s  at bus %s dev %s\n' "$pid" "$(cat "$d/manufacturer" 2>/dev/null)" "$(cat "$d/product" 2>/dev/null)" "$(cat "$d/busnum")" "$(cat "$d/devnum")"
  fi
done
if [ -z "$DEV" ]; then echo "FAIL: no Dynastream/Garmin ANT device (vendor 0fcf) found. Output of lsusb:"; lsusb 2>/dev/null; exit 1; fi
PID=$(cat "$DEV/idProduct")
case "$PID" in 1008|1009) ;; *) echo "WARN: product id $PID is not an ANT USB-2 (1008) / USB-m (1009) stick; Zwift's Windows driver only covers those two.";; esac
for i in "$DEV":*; do [ -e "$i/driver" ] && echo "Kernel driver on $(basename "$i"): $(basename "$(readlink "$i/driver")")"; done
NODE=$(printf '/dev/bus/usb/%03d/%03d' "$(cat "$DEV/busnum")" "$(cat "$DEV/devnum")")
ls -l "$NODE"

# 2. permissions
if [ ! -w "$NODE" ]; then
  echo "Device node is not writable by $USER - installing udev rule /etc/udev/rules.d/51-ant-usb.rules (sudo)"
  echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0fcf", ATTRS{idProduct}=="1008|1009", MODE="0666", TAG+="uaccess"' | sudo tee /etc/udev/rules.d/51-ant-usb.rules >/dev/null
  sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=0fcf
  sleep 2; ls -l "$NODE"
  [ -w "$NODE" ] || { echo "FAIL: still not writable - unplug and replug the stick, then rerun"; exit 2; }
fi
echo "OK: $NODE is writable"

# 3. wine
WINE="$(command -v wine || true)"
if [ -z "$WINE" ]; then
  WV=11.19; WD="$CACHE/wine-$WV-staging-amd64-wow64"
  if [ ! -x "$WD/bin/wine" ]; then
    echo "No system wine - downloading Wine $WV staging (Kron4ek build) to $CACHE"
    mkdir -p "$CACHE" && curl -fL "https://github.com/Kron4ek/Wine-Builds/releases/download/$WV/wine-$WV-staging-amd64-wow64.tar.xz" | tar xJ -C "$CACHE" || { echo "FAIL: download"; exit 3; }
  fi
  WINE="$WD/bin/wine"
fi
echo "Using $WINE ($("$WINE" --version))"

# 4. throwaway prefix with the bridge
export WINEPREFIX="$CACHE/ant-test-prefix" WINEDEBUG=-all
export WINEDLLPATH="$KIT/build" WINEDLLOVERRIDES="libusb0=b;winemenubuilder.exe=d"
mkdir -p "$CACHE"
if [ ! -d "$WINEPREFIX/drive_c/windows/system32" ]; then
  echo "Creating test prefix $WINEPREFIX ..."
  rm -rf "$WINEPREFIX"
  WINEDEBUG=err "$WINE" wineboot -i > "$CACHE/wineboot.log" 2>&1
  "${WINE%/wine}/wineserver" -w 2>/dev/null || wineserver -w 2>/dev/null
  [ -d "$WINEPREFIX/drive_c/windows/system32" ] || { echo "FAIL: wineboot could not create the prefix:"; tail -20 "$CACHE/wineboot.log"; exit 4; }
fi
cp -f "$KIT/build/placeholder/libusb0.dll" "$WINEPREFIX/drive_c/windows/system32/libusb0.dll"

# 5. run
echo "== antprobe.exe"
"$WINE" "$KIT/test/antprobe.exe"; rc=$?
echo "== exit code $rc (0 = success)"
[ -e "$DEV:1.0/driver" ] && echo "(Kernel driver re-attach: replug the stick if another Linux app needs it.)"
echo "Saved to $OUT"

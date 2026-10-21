#!/usr/bin/env bash
# zwift - start Zwift (Windows version) through GE-Proton. Installed by zwift-linux.
#   zwift            start Zwift
#   zwift doctor     check Bluetooth / ANT+ / install health
#   zwift kill       force-stop everything in the Zwift prefix
#   zwift log        show the path of the last run's log
#   zwift reset-bluetooth   forget Wine's cached Bluetooth devices (fixes "pairing never completes")
set -u
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
DATA="$(dirname "$SELF")"
# shellcheck source=/dev/null
. "$DATA/zwift.conf" || { echo "zwift: $DATA/zwift.conf missing - re-run install.sh" >&2; exit 1; }

export WINEPREFIX="$PFX" PROTONPATH="$GE" GAMEID="umu-zwift"
export PROTON_ENABLE_WINEBTH="$DO_BLE"   # Bluetooth LE trainers / HR / Zwift Play (GE-Proton 11-8+)
export WINEDLLOVERRIDES="libusb0=b;vccorlib140=n,b;winemenubuilder.exe=d"   # libusb0=b: ANT+ bridge
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--no-sandbox --disable-gpu"   # launcher web view under Wine
export PROTON_USE_XALIA=0                # Proton's gamepad helper can't read the launcher and floods the log
ZDIR="$PFX/drive_c/Program Files (x86)/Zwift"
LOG="$DATA/last-run.log"

# Bluetooth devices Wine has seen (from the prefix registry), as AA:BB:CC:DD:EE:FF
ble_known() {
  grep -oiE '_ORG_BLUEZ_HCI[0-9]+&[0-9A-F]{12}' "$PFX/system.reg" 2>/dev/null | grep -oiE '[0-9A-F]{12}$' \
    | tr 'a-f' 'A-F' | sort -u | sed 's/../&:/g; s/:$//'
}
# Wine is stopped with wineserver -k, so its Bluetooth driver never tells BlueZ to let go of the
# devices. A device left connected to the PC can't be connected again by the next session, so
# disconnect the ones Zwift used (only the PC's own connections; phones/watches are unaffected).
ble_release() {
  [ "$DO_BLE" = 1 ] && command -v bluetoothctl >/dev/null || return 0
  local mac
  for mac in $(ble_known); do
    if timeout 5 bluetoothctl info "$mac" 2>/dev/null | grep -q 'Connected: yes'; then
      timeout 5 bluetoothctl disconnect "$mac" >/dev/null 2>&1 && echo "Released Bluetooth device $mac"
    fi
  done
}

# If the adapter can't start a scan (BlueZ "org.bluez.Error.InProgress", e.g. a connection attempt
# left over from a killed session), Wine's StartDiscovery fails and Zwift never retries, so no
# Bluetooth device ever appears. Test-scan first and power-cycle the adapter if it is stuck.
ble_preflight() {
  [ "$DO_BLE" = 1 ] && command -v bluetoothctl >/dev/null || return 0
  local out
  out="$(timeout 10 bluetoothctl --timeout 3 scan on 2>&1)"
  if printf '%s' "$out" | grep -qE 'InProgress|Failed to start discovery'; then
    echo "Bluetooth adapter is busy (stale scan or connection) - resetting it..."
    timeout 10 bluetoothctl power off >/dev/null 2>&1; sleep 2
    timeout 10 bluetoothctl power on >/dev/null 2>&1; sleep 2
    out="$(timeout 10 bluetoothctl --timeout 3 scan on 2>&1)"
    if printf '%s' "$out" | grep -qE 'InProgress|Failed to start discovery'; then
      echo "Warning: Bluetooth scanning still fails; Bluetooth devices may not appear in Zwift." >&2
    else
      echo "Bluetooth adapter reset - scanning works."
    fi
  fi
}

case "${1:-}" in
  doctor) exec "$DATA/zwift-doctor.sh" ;;
  kill)   "$GE/files/bin/wineserver" -k; exit $? ;;
  log)    echo "$LOG"; exit 0 ;;
  reset-bluetooth)
    if pgrep -f 'Zwift(App|Launcher)\.exe' >/dev/null; then echo "Quit Zwift first." >&2; exit 1; fi
    "$GE/files/bin/wineserver" -k 2>/dev/null; "$GE/files/bin/wineserver" -w 2>/dev/null   # registry flushed
    ble_release
    R="$PFX/system.reg"; B="$R.bak-$(date +%Y%m%d-%H%M%S)"
    cp -p "$R" "$B" || exit 1
    # drop every registry key of a Bluetooth device / GATT service (…_ORG_BLUEZ_HCI0&<address>…),
    # keep the radio itself and everything else
    awk 'BEGIN{RS=""; ORS="\n\n"} { h=$0; sub(/\n.*/, "", h)
         if (toupper(h) ~ /_ORG_BLUEZ_HCI[0-9]+&[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]/) { n++; next }
         print } END { print n+0 > "/dev/stderr" }' "$B" > "$R.tmp" 2>"$R.count" && mv "$R.tmp" "$R"
    echo "Removed $(cat "$R.count") cached Bluetooth entries (backup: $B). Pair your devices again in Zwift."
    rm -f "$R.count"; exit 0 ;;
  -h|--help) sed -n '2,7p' "$SELF"; exit 0 ;;
esac

if pgrep -f 'ZwiftApp\.exe' >/dev/null; then echo "Zwift is already running."; exit 0; fi
[ -f "$ZDIR/ZwiftLauncher.exe" ] || { echo "Zwift is not installed in $PFX - run install.sh" >&2; exit 1; }
# Zwift's updater can put the Windows libusb0.dll back; keep the ANT+ bridge placeholder in place.
[ "$DO_ANT" = 1 ] && [ -f "$DATA/libusb0-placeholder.dll" ] && \
  cp -f "$DATA/libusb0-placeholder.dll" "$PFX/drive_c/windows/system32/libusb0.dll"

ble_release   # in case a previous session crashed or was killed
ble_preflight
cd "$ZDIR" || exit 1
echo "Starting Zwift (log: $LOG)"
"$UMU" "$ZDIR/ZwiftLauncher.exe" "$@" >"$LOG" 2>&1 &
UMU_PID=$!

# The launcher stays in the tray after the game quits and keeps the prefix alive.
# Once ZwiftApp.exe has run and exited, shut the prefix down so the session ends.
seen=0
while kill -0 "$UMU_PID" 2>/dev/null; do
  if pgrep -f 'ZwiftApp\.exe' >/dev/null; then
    seen=1
  elif [ "$seen" = 1 ]; then
    sleep 3
    pgrep -f 'ZwiftApp\.exe' >/dev/null || { "$GE/files/bin/wineserver" -k 2>/dev/null; break; }
  fi
  sleep 2
done
wait "$UMU_PID" 2>/dev/null
ble_release
echo "Zwift closed."
exit 0

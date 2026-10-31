#!/usr/bin/env bash
# Zwift for Linux - uninstaller
#   ./uninstall.sh            sign out of Zwift and remove the runner, umu copy, zwift command, menu entry,
#                             udev rules and AppArmor profile
#   ./uninstall.sh --purge    also delete the Zwift prefix (the installed game and its local settings;
#                             your rides and profile live in your Zwift account and are not affected)
set -u
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/zwift-linux"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1
PFX="${ZWIFT_PREFIX:-$HOME/Games/zwift}"
GE=""
# shellcheck source=/dev/null
[ -f "$DATA/zwift.conf" ] && . "$DATA/zwift.conf"

if pgrep -f 'Zwift(App|Launcher)\.exe' >/dev/null 2>&1; then
  if [ -n "$GE" ] && [ -x "$GE/files/bin/wineserver" ]; then WINEPREFIX="$PFX" "$GE/files/bin/wineserver" -k; sleep 2
  else echo "Quit Zwift first."; exit 1; fi
fi

[ -L "$HOME/.local/bin/zwift" ] || grep -qs 'zwift-setup.sh\|zwift-linux' "$HOME/.local/bin/zwift" && rm -f "$HOME/.local/bin/zwift" && echo "removed ~/.local/bin/zwift"
rm -f "$APPS/zwift-linux.desktop"
grep -qs 'Windows build via GE-Proton' "$APPS/zwift.desktop" && rm -f "$APPS/zwift.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null
echo "removed app menu entry"

[ -f "$DATA/zwift-auth.py" ] && python3 "$DATA/zwift-auth.py" logout >/dev/null 2>&1   # end the Zwift session
if [ -d "$DATA" ]; then rm -rf "$DATA" && echo "removed $DATA (GE-Proton runner, umu-launcher copy, ANT+ bridge)"; fi
[ -d "$HOME/.cache/ge-proton-ble" ] && rm -rf "$HOME/.cache/ge-proton-ble" && echo "removed old Bluetooth patch build cache"

for f in /etc/udev/rules.d/51-zwift-ant-usb.rules /etc/udev/rules.d/51-ant-usb.rules /etc/udev/rules.d/52-zwift-bluetooth-awake.rules; do
  if [ -f "$f" ]; then
    echo "removing $f (sudo)"
    sudo rm -f "$f" && sudo udevadm control --reload-rules
  fi
done
if [ -f /etc/apparmor.d/zwift-linux-umu ]; then
  echo "removing /etc/apparmor.d/zwift-linux-umu (sudo)"
  sudo apparmor_parser -R /etc/apparmor.d/zwift-linux-umu 2>/dev/null; sudo rm -f /etc/apparmor.d/zwift-linux-umu
fi

if [ "$PURGE" = 1 ]; then
  if [ -d "$PFX" ]; then
    read -r -p "Delete the Zwift prefix $PFX (installed game + local settings)? [y/N] " a </dev/tty
    case "$a" in y|Y|yes) rm -rf "$PFX" && echo "removed $PFX" ;; *) echo "kept $PFX" ;; esac
  fi
else
  echo "kept the Zwift prefix $PFX (use --purge to delete it)"
fi
echo "Done."

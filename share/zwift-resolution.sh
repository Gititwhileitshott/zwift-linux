# zwift-resolution.sh - Zwift's render resolution. Sourced by install.sh, zwift-launcher.sh and zwift-doctor.sh.
# shellcheck shell=bash
#
# Zwift chooses a graphics profile from the GPU it detects and offers resolutions only up to that
# profile's limit. Under Wine it often fails to recognise the GPU (an empty model string in Log.txt),
# falls back to a low profile and stops at 1080p even on a 1440p or 4K screen. Zwift renders at the
# USER_RESOLUTION_PREF value in prefs.xml, so zwift-linux writes the screen's own resolution there.
#
# RESOLUTION in zwift.conf:
#   WxH    (e.g. 3840x2160) written into prefs.xml once; changes made in Zwift's settings afterwards stick
#   auto   Zwift picks the resolution itself (zwift reset-resolution)
# The installer sets it to the largest connected screen's native resolution (install.sh --resolution).

# Native resolution of the largest connected screen, as WxH (empty if unknown).
# Reads the kernel's mode list, so it's the panel's real size whatever the desktop's scaling.
zl_native_res() {
  local c m best="" bestpx=0 w h
  for c in /sys/class/drm/card[0-9]*-*; do
    [ "$(cat "$c/status" 2>/dev/null)" = connected ] || continue
    m="$(head -1 "$c/modes" 2>/dev/null)"           # first mode = the screen's preferred (native) one
    [[ "$m" =~ ^([0-9]+)x([0-9]+) ]] || continue
    w="${BASH_REMATCH[1]}" h="${BASH_REMATCH[2]}"
    [ $(( w * h )) -gt "$bestpx" ] && bestpx=$(( w * h )) best="${w}x${h}"
  done
  if [ -z "$best" ] && command -v python3 >/dev/null; then   # no DRM mode list: ask GTK (logical size x scale)
    best="$(python3 -c 'import gi; gi.require_version("Gtk", "4.0"); from gi.repository import Gtk, Gdk
Gtk.init(); ms = Gdk.Display.get_default().get_monitors(); best = (0, 0)
for i in range(ms.get_n_items()):
    m = ms.get_item(i); g = m.get_geometry()
    s = m.get_scale() if hasattr(m, "get_scale") else m.get_scale_factor()
    best = max(best, (round(g.width * s), round(g.height * s)), key=lambda r: r[0] * r[1])
print("%dx%d" % best if best[0] else "")' 2>/dev/null)"
  fi
  echo "$best"
}

zl_valid_res() { [[ "${1:-}" =~ ^[0-9]{3,5}x[0-9]{3,5}$ ]]; }

# Zwift's prefs.xml files in the prefix (AppData\Local in current builds, Documents in older ones)
zl_prefs_files() {
  local p
  for p in "$PFX"/drive_c/users/*/AppData/Local/Zwift/prefs.xml "$PFX"/drive_c/users/*/Documents/Zwift/prefs.xml; do
    [ -f "$p" ] && echo "$p"
  done
}

# zl_apply_resolution: write RESOLUTION into prefs.xml once per value. $DATA/resolution.applied remembers
# what was written, so a resolution picked later in Zwift's settings isn't overwritten at every start.
# prefs.xml only exists after Zwift's first start, so zwift calls this both before and after the game runs.
zl_apply_resolution() {
  local r="${RESOLUTION:-auto}" p done=0
  zl_valid_res "$r" || return 0
  [ "$(cat "$DATA/resolution.applied" 2>/dev/null)" = "$r" ] && return 0
  while IFS= read -r p; do
    if grep -q '<USER_RESOLUTION_PREF>' "$p"; then
      sed -i "s#<USER_RESOLUTION_PREF>[^<]*</USER_RESOLUTION_PREF>#<USER_RESOLUTION_PREF>$r</USER_RESOLUTION_PREF>#" "$p"
    else
      sed -i "s#</CONFIG>#    <USER_RESOLUTION_PREF>$r</USER_RESOLUTION_PREF>\n    </CONFIG>#" "$p"
    fi
    grep -q "<USER_RESOLUTION_PREF>$r<" "$p" && done=1
  done < <(zl_prefs_files)
  [ "$done" = 1 ] && echo "$r" > "$DATA/resolution.applied" && echo "Zwift resolution set to $r (zwift reset-resolution lets Zwift choose again)"
  return 0
}

# zl_set_conf_resolution VALUE: store RESOLUTION=VALUE in zwift.conf
zl_set_conf_resolution() {
  local conf="$DATA/zwift.conf"
  if grep -q '^RESOLUTION=' "$conf"; then sed -i "s#^RESOLUTION=.*#RESOLUTION=\"$1\"#" "$conf"
  else echo "RESOLUTION=\"$1\"" >> "$conf"; fi
  RESOLUTION="$1"
}

# zl_clear_resolution: remove the forced resolution from prefs.xml (backup kept) so Zwift picks its own again
zl_clear_resolution() {
  local p n=0
  while IFS= read -r p; do
    grep -q '<USER_RESOLUTION_PREF>' "$p" || continue
    cp -p "$p" "$p.bak-$(date +%Y%m%d-%H%M%S)"
    sed -i '/<USER_RESOLUTION_PREF>/{s#<USER_RESOLUTION_PREF>[^<]*</USER_RESOLUTION_PREF>##; /^[[:space:]]*$/d}' "$p"
    n=$(( n + 1 ))
  done < <(zl_prefs_files)
  rm -f "$DATA/resolution.applied"
  zl_set_conf_resolution auto
  echo "Cleared the resolution in $n prefs.xml file(s) (backups kept next to them). Zwift chooses its own resolution from the next start."
}

# zwift-display.sh - choose Wine's display driver for the game. Sourced by zwift-launcher.sh and zwift-doctor.sh.
#
# ZwiftApp.exe draws with OpenGL. Wine can show it through X11 (winex11; on a Wayland desktop that means
# XWayland) or natively through Wayland (winewayland, OpenGL via EGL). Which one works depends on the
# session type and the GPU driver:
#
#   X11 session (any GPU)            x11      the only choice
#   Wayland + NVIDIA >= 595          wayland  XWayland on GNOME 51 + NVIDIA 615: the game renders but the window
#                                             never updates ("steam_app_0 is not responding"); winewayland works
#   Wayland + NVIDIA < 595           x11      winewayland is reported to freeze on NVIDIA 570 and older
#                                             (Proton-EM requires 595+); update the driver if XWayland freezes too
#   Wayland + Mesa (AMD/Intel/NVK)   x11      verified on AMD 890M and Renoir + GNOME; winewayland is the fallback
#
# Overrides, highest first: zwift --display x11|wayland, ZWIFT_DISPLAY=x11|wayland (environment or zwift.conf),
# then $DATA/display.auto, which zwift writes when the chosen driver failed to start OpenGL last time.

# Prints the GPU driver in use for the display: nvidia, amdgpu, i915, xe, nouveau, radeon, ... or unknown
zl_gpu_driver() {
  local d drv boot=""
  for d in /sys/class/drm/card[0-9]*; do
    [ -e "$d/device/driver" ] || continue
    case "$d" in *-*) continue ;; esac              # connectors (card0-HDMI-A-1), not GPUs
    drv="$(basename "$(readlink -f "$d/device/driver")")"
    # prefer the GPU that drives the boot display (laptops with two GPUs)
    if [ "$(cat "$d/device/boot_vga" 2>/dev/null)" = 1 ]; then boot="$drv"; break; fi
    [ -n "$boot" ] || boot="$drv"
  done
  echo "${boot:-unknown}"
}

zl_nvidia_major() { sed -n 's/^\([0-9]*\)\..*/\1/p' "${ZL_NVIDIA_VERSION_FILE:-/sys/module/nvidia/version}" 2>/dev/null || true; }

zl_session() {
  if [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ]; then echo wayland
  elif [ -n "${DISPLAY:-}" ]; then echo x11
  else echo none; fi
}

# zl_pick_display [override] -> sets ZL_DISPLAY (x11|wayland) and ZL_DISPLAY_WHY
zl_pick_display() {
  local want="${1:-${ZWIFT_DISPLAY:-}}" sess drv nv
  sess="$(zl_session)" drv="$(zl_gpu_driver)" nv="$(zl_nvidia_major)"
  if [ "$sess" != wayland ]; then
    ZL_DISPLAY=x11 ZL_DISPLAY_WHY="X11 session"; return
  fi
  case "$want" in
    x11|wayland) ZL_DISPLAY="$want" ZL_DISPLAY_WHY="set by you"; return ;;
  esac
  if [ -s "$DATA/display.auto" ]; then
    ZL_DISPLAY="$(cat "$DATA/display.auto")" ZL_DISPLAY_WHY="the other driver failed to start OpenGL last time"
    return
  fi
  if [ "$drv" = nvidia ] && [ -n "$nv" ] && [ "$nv" -lt 595 ]; then
    ZL_DISPLAY=x11 ZL_DISPLAY_WHY="NVIDIA $nv is too old for Wine's Wayland driver (595+); if the window freezes, update the driver"
  elif [ "$drv" = nvidia ]; then
    ZL_DISPLAY=wayland ZL_DISPLAY_WHY="NVIDIA on Wayland: the game window freezes under XWayland"
  else
    ZL_DISPLAY=x11 ZL_DISPLAY_WHY="$drv (Mesa) on Wayland: XWayland is the tested path"
  fi
}

# zl_apply_display: export what Proton needs for $ZL_DISPLAY
zl_apply_display() {
  if [ "$ZL_DISPLAY" = wayland ]; then export PROTON_ENABLE_WAYLAND=1; else unset PROTON_ENABLE_WAYLAND; fi
}

# zl_check_display GAMELOG: after a run, remember to use the other driver next time if OpenGL failed to start
zl_check_display() {
  local glog="$1" other
  [ "$(zl_session)" = wayland ] && [ -f "$glog" ] || return 0
  grep -q 'Failed to get sufficient openGL implementation' "$glog" || return 0
  if [ "$ZL_DISPLAY" = wayland ]; then other=x11; else other=wayland; fi
  echo "$other" > "$DATA/display.auto"
  echo "Zwift could not start OpenGL through $ZL_DISPLAY; the next start will use $other." >&2
}

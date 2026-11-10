#!/usr/bin/env python3
"""Remember the Zwift window's size and position between launches (X11 / XWayland).

    zwift-window.py STATE_FILE        X11/XWayland: restore the saved size and position, then save
                                      changes until Zwift closes
    zwift-window.py --prefs-size PREFS LOG
                                      any display driver: after Zwift closes, copy the last window size
                                      from Zwift's Log.txt into prefs.xml so the next start opens at it
    zwift-window.py --show | --list   print the Zwift window's geometry / every X11 window's class

Zwift only stores a window size in prefs.xml, never its position, and it does not save a size
changed by dragging the window. Under Wine's Wayland driver no other program may move or read a
window, so there only the size is kept (through prefs.xml); the compositor places the window.
"""
import ctypes as C, os, re, sys, time


def prefs_size(prefs, log):
    """Write the last framebuffer size Zwift logged into prefs.xml (WINWIDTH/WINHEIGHT)."""
    try:
        text = open(log, errors="replace").read()
        xml = open(prefs, errors="replace", newline="").read()
    except OSError:
        return
    sizes = re.findall(r"\] (?:FB )?resize: (\d+) x (\d+)", text)
    if not sizes or "<FULLSCREEN>1</FULLSCREEN>" in xml:
        return
    w, h = (int(v) for v in sizes[-1])
    if w < 640 or h < 360:
        return
    biggest = largest_monitor_pixels()
    if biggest and (w > biggest[0] or h > biggest[1]):
        return                         # bigger than any screen now: keep what prefs.xml has
    for key, val in (("WINWIDTH", w), ("WINHEIGHT", h)):
        if f"<{key}>" in xml:
            xml = re.sub(f"<{key}>[^<]*</{key}>", f"<{key}>{val}</{key}>", xml)
        else:
            nl = "\r\n" if "\r\n" in xml else "\n"
            xml = xml.replace("</CONFIG>", f"    <{key}>{val}</{key}>{nl}    </CONFIG>", 1)
    with open(prefs + ".tmp", "w", newline="") as f:
        f.write(xml)
    os.replace(prefs + ".tmp", prefs)
    print(f"window size {w}x{h} saved in prefs.xml")


def largest_monitor_pixels():
    try:
        import gi
        gi.require_version("Gtk", "4.0")
        from gi.repository import Gtk, Gdk
        Gtk.init()
        mons = Gdk.Display.get_default().get_monitors()
        out = []
        for i in range(mons.get_n_items()):
            m = mons.get_item(i); g = m.get_geometry()
            scale = m.get_scale() if hasattr(m, "get_scale") else m.get_scale_factor()
            # XWayland with fractional scaling renders at the next whole scale, so allow for that.
            scale = max(scale, float(-(-scale // 1)))
            out.append((round(g.width * scale), round(g.height * scale)))
        return max(out, key=lambda v: v[0] * v[1]) if out else None
    except Exception:
        return None


if sys.argv[1:2] == ["--prefs-size"] and len(sys.argv) == 4:
    prefs_size(sys.argv[2], sys.argv[3])
    sys.exit(0)

x = C.CDLL("libX11.so.6")
x.XOpenDisplay.restype = C.c_void_p
x.XOpenDisplay.argtypes = [C.c_char_p]
x.XDefaultRootWindow.restype = C.c_ulong
x.XDefaultRootWindow.argtypes = [C.c_void_p]
x.XQueryTree.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_ulong),
                         C.POINTER(C.POINTER(C.c_ulong)), C.POINTER(C.c_uint)]
x.XFree.argtypes = [C.c_void_p]
x.XSync.argtypes = [C.c_void_p, C.c_int]
x.XMoveResizeWindow.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_int, C.c_uint, C.c_uint]
x.XGetGeometry.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_int), C.POINTER(C.c_int),
                           C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint)]
x.XTranslateCoordinates.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong, C.c_int, C.c_int, C.POINTER(C.c_int),
                                    C.POINTER(C.c_int), C.POINTER(C.c_ulong)]


class ClassHint(C.Structure):
    _fields_ = [("name", C.c_char_p), ("cls", C.c_char_p)]


x.XGetClassHint.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(ClassHint)]
# A window that vanishes between XQueryTree and the next call must not abort the program.
HandlerType = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_void_p)
HANDLER = HandlerType(lambda _d, _e: 0)
x.XSetErrorHandler.argtypes = [HandlerType]
x.XSetErrorHandler(HANDLER)
d = x.XOpenDisplay(None)
if not d:
    sys.exit("zwift-window: no X display")
root = x.XDefaultRootWindow(d)


def children(win):
    r, p, kids, n = C.c_ulong(), C.c_ulong(), C.POINTER(C.c_ulong)(), C.c_uint()
    if not x.XQueryTree(d, win, C.byref(r), C.byref(p), C.byref(kids), C.byref(n)):
        return []
    out = [kids[i] for i in range(n.value)]
    if n.value:
        x.XFree(kids)
    return out


def zwift_windows(win, out):
    hint = ClassHint()
    if x.XGetClassHint(d, win, C.byref(hint)):
        # Wine names the class after the program; Proton uses steam_app_<game id> (steam_app_zwift here).
        names = ((hint.name or b"") + b" " + (hint.cls or b"")).lower()
        if b"zwiftapp" in names or b"steam_app_zwift" in names or b"umu-zwift" in names:
            out.append(win)
    for kid in children(win):
        zwift_windows(kid, out)
    return out


def find(win):
    best, area = None, 0
    for w in zwift_windows(win, []):
        g = geometry(w)
        if g and g[2] >= 400 and g[3] >= 300 and g[2] * g[3] > area:
            best, area = w, g[2] * g[3]
    return best


def geometry(win):
    r, gx, gy = C.c_ulong(), C.c_int(), C.c_int()
    w, h, b, dp = C.c_uint(), C.c_uint(), C.c_uint(), C.c_uint()
    if not x.XGetGeometry(d, win, C.byref(r), C.byref(gx), C.byref(gy), C.byref(w), C.byref(h), C.byref(b), C.byref(dp)):
        return None
    rx, ry, c = C.c_int(), C.c_int(), C.c_ulong()
    x.XTranslateCoordinates(d, win, root, 0, 0, C.byref(rx), C.byref(ry), C.byref(c))
    return rx.value, ry.value, w.value, h.value


def apply(win, want):
    # The window manager may offset a request by the title bar, so correct from what actually happened.
    tx, ty, w, h = want
    for _ in range(4):
        x.XMoveResizeWindow(d, win, tx, ty, w, h)
        x.XSync(d, 0)
        time.sleep(0.5)
        now = geometry(win)
        if not now or now == tuple(want):
            return
        tx += want[0] - now[0]
        ty += want[1] - now[1]


class MonitorInfo(C.Structure):
    _fields_ = [("name", C.c_ulong), ("primary", C.c_int), ("automatic", C.c_int), ("noutput", C.c_int),
                ("x", C.c_int), ("y", C.c_int), ("width", C.c_int), ("height", C.c_int),
                ("mwidth", C.c_int), ("mheight", C.c_int), ("outputs", C.c_void_p)]


def monitors():
    """Monitor rectangles in X screen coordinates; the whole screen if XRandR is unavailable."""
    try:
        xr = C.CDLL("libXrandr.so.2")
        xr.XRRGetMonitors.restype = C.POINTER(MonitorInfo)
        xr.XRRGetMonitors.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.POINTER(C.c_int)]
        xr.XRRFreeMonitors.argtypes = [C.POINTER(MonitorInfo)]
        n = C.c_int()
        info = xr.XRRGetMonitors(d, root, 1, C.byref(n))
        rects = [(info[i].x, info[i].y, info[i].width, info[i].height) for i in range(n.value)]
        if info:
            xr.XRRFreeMonitors(info)
        if rects:
            return rects
    except OSError:
        pass
    x.XDisplayWidth.argtypes = x.XDisplayHeight.argtypes = [C.c_void_p, C.c_int]
    return [(0, 0, x.XDisplayWidth(d, 0), x.XDisplayHeight(d, 0))]


def safe_target(want, now):
    """Return the geometry to restore: the saved one if it still fits a monitor, else the saved size
    (shrunk to fit if needed) at the window's current position, or None to leave the window alone."""
    wx, wy, ww, wh = want
    mons = monitors()
    def overlap(m):
        ox = max(0, min(wx + ww, m[0] + m[2]) - max(wx, m[0]))
        oy = max(0, min(wy + wh, m[1] + m[3]) - max(wy, m[1]))
        return ox * oy
    best = max(mons, key=overlap)
    if overlap(best) >= 0.9 * ww * wh:
        return want                    # the saved place is still on a screen
    # The screen layout changed: keep the size if it fits the monitor the window is on now.
    cx, cy = now[0] + now[2] // 2, now[1] + now[3] // 2
    here = next((m for m in mons if m[0] <= cx < m[0] + m[2] and m[1] <= cy < m[1] + m[3]), mons[0])
    f = min(1.0, here[2] / ww, here[3] / wh)
    ww, wh = int(ww * f), int(wh * f)
    nx = min(max(now[0], here[0]), here[0] + here[2] - ww)
    ny = min(max(now[1], here[1]), here[1] + here[3] - wh)
    return (nx, ny, ww, wh)


if sys.argv[1:] == ["--monitors"]:
    print(monitors())
    sys.exit(0)
if sys.argv[1:] == ["--show"]:
    win = find(root)
    print(geometry(win) if win else "no Zwift window")
    sys.exit(0)
if sys.argv[1:] == ["--list"]:
    def walk(w, depth=0):
        hint = ClassHint()
        if x.XGetClassHint(d, w, C.byref(hint)):
            print(hint.name, hint.cls, geometry(w))
        for k in children(w):
            walk(k, depth + 1)
    walk(root)
    sys.exit(0)

state = sys.argv[1]
want = None
if os.path.exists(state):
    want = tuple(int(v) for v in open(state).read().split())

win = None
for _ in range(600):                 # wait up to 10 minutes for the game to open
    win = find(root)
    if win:
        break
    time.sleep(1)
if not win:
    sys.exit(0)

time.sleep(8)                        # let the game finish creating and sizing its window
if want and len(want) == 4:
    target = safe_target(want, geometry(win) or want)
    if target != want:
        print(f"screen layout changed; restoring {target} instead of {want}", flush=True)
    apply(win, target)

last = geometry(win)
while True:
    time.sleep(5)
    now = geometry(win)
    if not now:
        break
    if now != last and now[2] > 200 and now[3] > 200:
        last = now
        with open(state + ".tmp", "w") as f:
            f.write(" ".join(str(v) for v in now))
        os.replace(state + ".tmp", state)

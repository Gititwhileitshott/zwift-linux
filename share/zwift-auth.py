#!/usr/bin/env python3
"""zwift-auth - sign in to Zwift on Linux without the Windows launcher. Installed by zwift-linux.

Does what ZwiftLauncher.exe does before it starts the game, with Zwift's normal login endpoints:
  1. GET  <GAME_URL>/api/auth                       -> Keycloak realm + auth base URL
  2. open <auth>/realms/<realm>/protocol/openid-connect/auth?client_id=Game_Launcher
          &redirect_uri=http://zwift/&response_type=code   (Zwift's own sign-in page)
  3. catch the redirect to http://zwift/?code=...
  4. POST <auth>/realms/<realm>/protocol/openid-connect/token  (grant_type=authorization_code)
  5. ZwiftApp.exe --launcher_version=<v> --token=<the token response JSON>

The refresh token is kept (mode 600) so later starts don't need the sign-in page.

  zwift-auth.py login              sign in (opens Zwift's sign-in page in a small window)
  zwift-auth.py token FILE         write a fresh token JSON to FILE (refresh, or sign in if needed)
  zwift-auth.py status             show whether you are signed in
  zwift-auth.py logout             end the Zwift session and forget the stored token
"""
import json, os, sys, time, urllib.error, urllib.parse, urllib.request, webbrowser

GAME_URL = os.environ.get("ZWIFT_GAME_URL", "https://us-or-rly101.zwift.com")
CLIENT_ID = "Game_Launcher"
REDIRECT = "http://zwift/"
DATA = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "zwift-linux")
STORE = os.path.join(DATA, "auth.json")
UA = "zwift-linux/1.1.0"


def http(url, form=None):
    data = urllib.parse.urlencode(form).encode() if form is not None else None
    req = urllib.request.Request(url, data=data, headers={"Accept": "application/json", "User-Agent": UA})
    if data is not None:
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def endpoints():
    st, body = http(GAME_URL.rstrip("/") + "/api/auth")
    if st != 200:
        sys.exit(f"zwift-auth: {GAME_URL}/api/auth returned HTTP {st}")
    info = json.loads(body)
    base = info["url"].rstrip("/") + "/realms/" + info["realm"] + "/protocol/openid-connect"
    return base


def load():
    try:
        with open(STORE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save(tok):
    os.makedirs(DATA, exist_ok=True)
    tok = dict(tok, _obtained=int(time.time()))
    fd = os.open(STORE + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(tok, f)
    os.replace(STORE + ".tmp", STORE)


def game_json(tok):
    """The token response exactly as Keycloak sent it (the launcher passes the body through)."""
    return tok.get("_raw") or json.dumps({k: v for k, v in tok.items() if not k.startswith("_")},
                                          separators=(",", ":"))


def token_request(base, form):
    st, body = http(base + "/token", dict(form, client_id=CLIENT_ID))
    if st != 200:
        return None, f"HTTP {st}: {body[:300]}"
    tok = json.loads(body)
    tok["_raw"] = body.strip()
    return tok, None


def ask_code_webkit(url):
    """Zwift's sign-in page in a GTK4/WebKit window; returns the ?code= of the http://zwift/ redirect."""
    import gi
    gi.require_version("Gtk", "4.0")
    gi.require_version("WebKit", "6.0")
    from gi.repository import GLib, Gtk, WebKit

    result = {}
    app = Gtk.Application(application_id="com.github.zwift_linux.auth")

    def on_activate(app):
        win = Gtk.ApplicationWindow(application=app, title="Sign in to Zwift", default_width=520, default_height=760)
        session = WebKit.NetworkSession.new_ephemeral()   # no cookies left on disk
        view = WebKit.WebView(network_session=session)

        def on_policy(view, decision, kind):
            if kind not in (WebKit.PolicyDecisionType.NAVIGATION_ACTION, WebKit.PolicyDecisionType.NEW_WINDOW_ACTION):
                return False
            uri = decision.get_navigation_action().get_request().get_uri()
            if uri.startswith(REDIRECT) or uri.startswith("http://zwift?"):
                q = urllib.parse.parse_qs(urllib.parse.urlsplit(uri).query)
                result["code"] = (q.get("code") or [None])[0]
                result["error"] = (q.get("error_description") or q.get("error") or [None])[0]
                decision.ignore()
                win.close()
                return True
            if kind == WebKit.PolicyDecisionType.NEW_WINDOW_ACTION:   # social sign-in popups: same window
                decision.ignore()
                view.load_uri(uri)
                return True
            return False

        view.connect("decide-policy", on_policy)
        win.set_child(view)
        view.load_uri(url)
        win.present()

    app.connect("activate", on_activate)
    app.run([])
    if result.get("error"):
        sys.exit(f"zwift-auth: sign-in failed: {result['error']}")
    return result.get("code")


def ask_code_browser(url):
    """Fallback without WebKitGTK: the browser ends on an unreachable http://zwift/?code=... page."""
    print("Opening Zwift's sign-in page in your browser. After you sign in, the browser will show an\n"
          "error page for http://zwift/ - copy that page's full address and paste it here.")
    webbrowser.open(url)
    line = input("Address: ").strip()
    return (urllib.parse.parse_qs(urllib.parse.urlsplit(line).query).get("code") or [None])[0]


def login(base):
    url = base + "/auth?" + urllib.parse.urlencode(
        {"client_id": CLIENT_ID, "redirect_uri": REDIRECT, "login": "true", "response_type": "code"})
    code = None
    if not os.environ.get("ZWIFT_AUTH_BROWSER"):
        try:
            code = ask_code_webkit(url)
        except (ImportError, ValueError) as e:
            print(f"zwift-auth: no WebKitGTK 6 window ({e}); using your browser instead.", file=sys.stderr)
            code = ask_code_browser(url)
    else:
        code = ask_code_browser(url)
    if not code:
        sys.exit("zwift-auth: sign-in was cancelled")
    # The launcher sends the redirect as "redirect_url"; Keycloak checks "redirect_uri". Send both.
    tok, err = token_request(base, {"grant_type": "authorization_code", "code": code,
                                    "redirect_uri": REDIRECT, "redirect_url": "http://zwift"})
    if not tok:
        sys.exit(f"zwift-auth: token exchange failed: {err}")
    save(tok)
    return tok


def fresh_token(base, interactive=True):
    tok = load()
    if tok and tok.get("refresh_token"):
        new, err = token_request(base, {"grant_type": "refresh_token", "refresh_token": tok["refresh_token"]})
        if new:
            save(new)
            return new
        print(f"zwift-auth: stored sign-in expired ({err.split(':')[0]}), signing in again", file=sys.stderr)
    if not interactive:
        sys.exit("zwift-auth: not signed in - run: zwift login")
    return login(base)


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "status"
    if cmd in ("-h", "--help", "help"):
        print(__doc__.split("\n\n", 2)[2]); return 0
    if cmd == "status":
        tok = load()
        if not tok:
            print("Not signed in."); return 1
        left = tok.get("_obtained", 0) + tok.get("refresh_expires_in", 0) - time.time()
        print("Signed in" + (f" (sign-in valid ~{int(left // 3600)} h more)" if tok.get("refresh_expires_in") else ""))
        return 0
    base = endpoints()
    if cmd == "login":
        login(base); print("Signed in to Zwift."); return 0
    if cmd == "token":
        if len(argv) < 3:
            sys.exit("usage: zwift-auth.py token FILE [--no-login]")
        tok = fresh_token(base, interactive="--no-login" not in argv)
        fd = os.open(argv[2], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(game_json(tok))
        return 0
    if cmd == "logout":
        tok = load()
        if tok and tok.get("refresh_token"):
            http(base + "/logout", {"client_id": CLIENT_ID, "refresh_token": tok["refresh_token"]})
        try:
            os.remove(STORE)
        except FileNotFoundError:
            pass
        print("Signed out."); return 0
    sys.exit(f"zwift-auth: unknown command {cmd!r} (try --help)")


if __name__ == "__main__":
    sys.exit(main(sys.argv))

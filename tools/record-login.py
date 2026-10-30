"""mitmproxy addon: record Zwift's login/token traffic with secrets removed. Part of zwift-linux.

  mitmdump -q -s tools/record-login.py --set zwift_log=login-flow.txt

Developer tool only, not installed by install.sh and not used by zwift-auth.py. Point a test copy of the
Windows launcher at the proxy (in a throwaway prefix that trusts ~/.mitmproxy's CA), sign in, and stop
mitmdump afterwards. Only zwift.com requests are logged; passwords, codes and tokens become <len N>.
"""
import json, urllib.parse
from mitmproxy import ctx

SECRET = {"password", "code", "access_token", "refresh_token", "id_token", "token", "session_state",
          "client_secret", "username", "email"}


def red(k, v):
    return f"<len {len(v)}>" if k.lower() in SECRET else v


def summarize(body, ctype):
    if not body:
        return ""
    if "x-www-form-urlencoded" in ctype:
        return "form " + json.dumps({k: red(k, v) for k, v in urllib.parse.parse_qsl(body.decode(errors="replace"))})
    if "json" in ctype:
        try:
            d = json.loads(body)
            if isinstance(d, dict):
                return "json " + json.dumps({k: red(k, str(v)) if k.lower() in SECRET else v for k, v in d.items()})
        except ValueError:
            pass
    return f"<{ctype or 'body'} {len(body)} bytes>"


def load(loader):
    loader.add_option("zwift_log", str, "login-flow.txt", "where to write the redacted log")


def response(flow):
    if "zwift" not in flow.request.pretty_host:
        return
    u = urllib.parse.urlsplit(flow.request.pretty_url)
    q = {k: red(k, v) for k, v in urllib.parse.parse_qsl(u.query)}
    loc = flow.response.headers.get("location", "")
    if loc:
        lu = urllib.parse.urlsplit(loc)
        loc = urllib.parse.urlunsplit(lu._replace(query=urllib.parse.urlencode(
            {k: red(k, v) for k, v in urllib.parse.parse_qsl(lu.query)})))
    with open(ctx.options.zwift_log, "a") as f:
        f.write(f"{flow.request.method} {u.scheme}://{u.netloc}{u.path} {json.dumps(q) if q else ''}\n")
        req = summarize(flow.request.content, flow.request.headers.get("content-type", ""))
        if req:
            f.write(f"  > {req}\n")
        f.write(f"  < {flow.response.status_code} {summarize(flow.response.content, flow.response.headers.get('content-type', ''))}"
                f"{'  location=' + loc if loc else ''}\n")

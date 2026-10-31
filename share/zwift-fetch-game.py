#!/usr/bin/env python3
"""zwift-fetch-game - download the Zwift game files straight from Zwift's update CDN.

This is what the Zwift launcher does before login: read Zwift_ver_cur.xml, fetch the
manifest it names, then download each file and check its CRC32. Doing it here lets
an install (or a test) get ZwiftApp.exe and its data without the WebView2 launcher.

Usage: zwift-fetch-game.py DEST [--jobs N] [--verify-only] [--if-outdated]
DEST is the Zwift install folder, e.g. "$WINEPREFIX/drive_c/Program Files (x86)/Zwift".
Files already present with the right size and CRC are skipped, so re-running resumes.
--if-outdated does nothing when DEST already has the current version (quick check before each start).
"""
import argparse, concurrent.futures as cf, os, sys, urllib.request, xml.etree.ElementTree as ET, zlib

ROOT = "https://cdn.zwift.com/gameassets/Zwift_Updates_Root/"   # HTTPS only, certificates verified


def get(url, tries=4):
    for i in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                if not r.geturl().startswith("https://"):   # never accept a redirect to plain HTTP
                    raise SystemExit(f"zwift-fetch-game: {url} redirected to {r.geturl()}; refusing non-HTTPS download")
                return r.read()
        except OSError as e:
            if i == tries - 1:
                raise
            print(f"retry {url}: {e}", file=sys.stderr)


def crc(path):
    c = 0
    with open(path, "rb") as f:
        while b := f.read(1 << 20):
            c = zlib.crc32(b, c)
    return c - (1 << 32) if c >= 1 << 31 else c  # manifest stores it as signed int32


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dest")
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--verify-only", action="store_true")
    ap.add_argument("--if-outdated", action="store_true")
    a = ap.parse_args()

    cur_raw = get(ROOT + "Zwift_ver_cur.xml")
    cur = ET.fromstring(cur_raw)
    local = os.path.join(a.dest, "Zwift_ver_cur.xml")
    if a.if_outdated and os.path.exists(local) and os.path.exists(os.path.join(a.dest, "ZwiftApp.exe")):
        try:
            if ET.parse(local).getroot().get("version") == cur.get("version"):
                return
        except ET.ParseError:
            pass
    print(f"Zwift {cur.get('sversion')}, manifest {cur.get('manifest')}")
    man_raw = get(ROOT + cur.get("manifest"))
    man = ET.fromstring(man_raw)
    folder = man.get("folder")
    files = [(f.findtext("path").replace("\\", "/"), int(f.findtext("length")), int(f.findtext("checksum")))
             for f in man.iter("file")]
    total = sum(n for _, n, _ in files)
    print(f"{len(files)} files, {total / 1e9:.2f} GB -> {a.dest}")

    def one(item):
        rel, size, want = item
        out = os.path.join(a.dest, rel)
        if os.path.exists(out) and os.path.getsize(out) == size and crc(out) == want:
            return rel, size, "ok"
        if a.verify_only:
            return rel, size, "bad"
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        data = get(ROOT + folder + "/" + urllib.request.quote(rel))
        c = zlib.crc32(data)
        if len(data) != size or (c - (1 << 32) if c >= 1 << 31 else c) != want:
            return rel, size, "crc mismatch"
        tmp = out + ".part"
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, out)
        return rel, size, "downloaded"

    done = bad = 0
    with cf.ThreadPoolExecutor(a.jobs) as ex:
        for i, (rel, size, st) in enumerate(ex.map(one, files), 1):
            done += size
            if st not in ("ok", "downloaded"):
                bad += 1
                print(f"{st}: {rel}", file=sys.stderr)
            if i % 500 == 0 or i == len(files):
                print(f"{i}/{len(files)} files, {done / 1e9:.2f}/{total / 1e9:.2f} GB, {bad} failed", flush=True)

    # The launcher keeps the current version files next to the game; keep copies for it.
    if bad:
        sys.exit(1)
    with open(local, "wb") as f:   # written last: marks the version as complete
        f.write(cur_raw)
    with open(os.path.join(a.dest, cur.get("manifest")), "wb") as f:
        f.write(man_raw)


if __name__ == "__main__":
    main()

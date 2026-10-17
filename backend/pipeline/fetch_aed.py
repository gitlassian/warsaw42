"""Refresh the AED snapshot from the Warsaw open data API.

    WARSAW_API_KEY=... python -m pipeline.fetch_aed [--photos]

Writes data/raw/scb_aed_list.json (latest) and appends a diff to data/raw/changes.jsonl.
On any API error the previous snapshot stays untouched and the exit code is non-zero.
"""
import argparse
import base64
import json
import os
import sys
import time
import urllib.request
from datetime import datetime, timezone

API = "https://dane.um.warszawa.pl/api/action/get_scb_lokalizacja_defibrylatorow"
ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "data")
RAW = os.path.join(ROOT, "raw", "scb_aed_list.json")
CHANGES = os.path.join(ROOT, "raw", "changes.jsonl")
PHOTOS = os.path.join(ROOT, "aed", "photos")


def post(body, key, tries=4, timeout=180):
    err = None
    for i in range(tries):
        try:
            req = urllib.request.Request(
                API, data=json.dumps(body).encode(), method="POST",
                headers={"Authorization": key, "Content-Type": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read())
        except Exception as e:
            err = e
            time.sleep(2 * (i + 1))
    raise RuntimeError(f"API failed: {err!r}")


def index(records):
    return {r["properties"]["defibrillator_id"]: r for r in records}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--photos", action="store_true", help="download photos for ids that have none yet")
    args = ap.parse_args()
    key = os.environ.get("WARSAW_API_KEY")
    if not key:
        sys.exit("WARSAW_API_KEY is not set")

    new = post({}, key)
    if not isinstance(new, list) or len(new) < 100:  # the API answers 500/odd bodies when unhappy
        sys.exit(f"suspicious response ({type(new).__name__}, len={len(new) if hasattr(new, '__len__') else '?'}), keeping old snapshot")

    old = {}
    if os.path.exists(RAW):
        with open(RAW, encoding="utf-8") as f:
            old = index(json.load(f))
    cur = index(new)
    diff = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "added": sorted(set(cur) - set(old)),
        "removed": sorted(set(old) - set(cur)),
        "changed": sorted(i for i in set(cur) & set(old) if cur[i] != old[i]),
        "total": len(cur),
    }
    os.makedirs(os.path.dirname(RAW), exist_ok=True)
    with open(RAW + ".tmp", "w", encoding="utf-8") as f:
        json.dump(new, f, ensure_ascii=False)
    os.replace(RAW + ".tmp", RAW)
    if old and (diff["added"] or diff["removed"] or diff["changed"]):
        with open(CHANGES, "a", encoding="utf-8") as f:
            f.write(json.dumps(diff, ensure_ascii=False) + "\n")
    print({k: (len(v) if isinstance(v, list) else v) for k, v in diff.items()})

    if args.photos:
        os.makedirs(PHOTOS, exist_ok=True)
        have = {os.path.splitext(n)[0] for n in os.listdir(PHOTOS)}
        for i in sorted(set(cur) - have):
            try:
                rec = post({"defibrillator_id": str(i)}, key)
                rec = rec[0] if isinstance(rec, list) else rec
                att = rec["properties"].get("attachment")
                if att:
                    raw = base64.b64decode(att)
                    ext = "png" if raw[:4] == b"\x89PNG" else "jpg"
                    with open(os.path.join(PHOTOS, f"{i}.{ext}"), "wb") as f:
                        f.write(raw)
            except Exception as e:  # e.g. id 2487 always returns 500
                print(f"photo {i}: {e!r}", file=sys.stderr)


if __name__ == "__main__":
    main()

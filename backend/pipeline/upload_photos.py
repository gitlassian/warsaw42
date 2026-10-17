"""Upload the EXIF-free AED photos to the public Supabase Storage bucket.

    SUPABASE_URL=https://<ref>.supabase.co SUPABASE_SECRET_KEY=... python3 backend/pipeline/upload_photos.py

Reads data/aed/photos_public/<defibrillator_id>.webp (pipeline/photos.py) and puts each file at
aed-photos/<defibrillator_id>.webp, the name aeds.photo_path stores. Existing objects are overwritten.
The key must be a secret (sb_secret_...) or legacy service_role key: anon may not write to Storage.
Never upload data/aed/photos/: the originals carry GPS in their EXIF.
"""
import argparse
import os
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(REPO, "data", "aed", "photos_public")
BUCKET = "aed-photos"


def headers(key):
    # Legacy keys are JWTs and go in both headers; sb_secret_ keys only in `apikey`.
    h = {"apikey": key, "Content-Type": "image/webp", "x-upsert": "true", "Cache-Control": "max-age=86400"}
    if key.startswith("eyJ"):
        h["Authorization"] = f"Bearer {key}"
    return h


def upload(job):
    name, url, key = job
    with open(os.path.join(SRC, name), "rb") as f:
        body = f.read()
    req = urllib.request.Request(f"{url}/storage/v1/object/{BUCKET}/{name}", data=body, method="POST", headers=headers(key))
    try:
        with urllib.request.urlopen(req, timeout=60):
            return name, None
    except urllib.error.HTTPError as e:
        return name, f"{e.code} {e.read()[:200]!r}"
    except Exception as e:  # one bad file must not stop the batch
        return name, repr(e)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=8)
    a = ap.parse_args()
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SECRET_KEY") or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        sys.exit("SUPABASE_URL and SUPABASE_SECRET_KEY (or SUPABASE_SERVICE_ROLE_KEY) must be set")
    if not os.path.isdir(SRC):
        sys.exit(f"{SRC} is missing: run pipeline/photos.py first")
    names = sorted(n for n in os.listdir(SRC) if n.endswith(".webp"))
    failed = {}
    with ThreadPoolExecutor(a.workers) as ex:
        for name, err in ex.map(upload, [(n, url, key) for n in names]):
            if err:
                failed[name] = err
                print(f"{name}: {err}", file=sys.stderr)
    print(f"{len(names) - len(failed)}/{len(names)} uploaded to {BUCKET}, failed: {len(failed)}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

"""Make public, EXIF-free copies of the AED photos.

    python3 backend/pipeline/photos.py [--max-side 800] [--quality 72]

Reads  data/aed/photos/<defibrillator_id>.(jpg|png)   originals (private: EXIF has GPS and the phone model)
Writes data/aed/photos_public/<defibrillator_id>.webp  resized copies, safe to serve
       data/aed/photos_public/manifest.json            size, dimensions and sha256 per file

The EXIF orientation is applied to the pixels before the metadata is dropped, so photos stay upright.
Also writes backend/data/out/aed_photos.json (ids that have a photo).
Upload photos_public/ to the aed-photos bucket with pipeline/upload_photos.py.
"""
import argparse
import hashlib
import json
import os
from concurrent.futures import ProcessPoolExecutor

from PIL import Image, ImageOps

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(REPO, "data", "aed", "photos")
OUT = os.path.join(REPO, "data", "aed", "photos_public")


def convert(job):
    name, max_side, quality = job
    sid = os.path.splitext(name)[0]
    try:
        with Image.open(os.path.join(SRC, name)) as im:
            im = ImageOps.exif_transpose(im)  # bake the rotation in, then the metadata can go
            im = im.convert("RGB")
            im.thumbnail((max_side, max_side), Image.LANCZOS)
            path = os.path.join(OUT, f"{sid}.webp")
            im.save(path, "WEBP", quality=quality, method=6)  # no exif=/icc_profile= arguments: nothing is carried over
            w, h = im.size
        data = open(path, "rb").read()
        return sid, {"file": f"{sid}.webp", "width": w, "height": h, "bytes": len(data),
                     "sha256": hashlib.sha256(data).hexdigest()}, None
    except Exception as e:  # a broken file must not stop the batch
        return sid, None, repr(e)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-side", type=int, default=800)
    ap.add_argument("--quality", type=int, default=72)
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    names = sorted(n for n in os.listdir(SRC) if n.lower().endswith((".jpg", ".jpeg", ".png")))
    manifest, failed = {}, {}
    with ProcessPoolExecutor() as ex:
        for sid, info, err in ex.map(convert, [(n, a.max_side, a.quality) for n in names], chunksize=8):
            if info:
                manifest[sid] = info
            else:
                failed[sid] = err
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump({"max_side": a.max_side, "quality": a.quality, "photos": manifest, "failed": failed}, f, indent=1)
    # committed list of ids that have a public photo, so pipeline.seed_sql needs no image files
    with open(os.path.join(REPO, "backend", "data", "out", "aed_photos.json"), "w", encoding="utf-8") as f:
        json.dump(sorted(manifest, key=int), f)
    total = sum(v["bytes"] for v in manifest.values())
    print(f"{len(manifest)} photos, {total / 1e6:.1f} MB total, avg {total / max(len(manifest), 1) / 1e3:.0f} KB, failed: {len(failed)}")


if __name__ == "__main__":
    main()

"""Assign each AED to a Warsaw district (OSM admin_level 9).

    python3 -m pipeline.districts

Reads  data/aed/../geo/osm_dzielnice_raw.json (repo-root data/, not committed) and data/out/aed.json
Writes data/out/aed_district.json  {source_id: district name}, committed so that pipeline.seed_sql needs no raw OSM file.
A point outside every district (the OSM and city boundaries differ by a few metres) gets the nearest district centre.
"""
import json
import os

from pipeline.seed import B, build_districts, log


def inside(pt, ring):
    x, y = pt
    c = False
    for i in range(len(ring) - 1):
        (x1, y1), (x2, y2) = ring[i], ring[i + 1]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def contains(geojson, pt):
    return any(inside(pt, poly[0]) and not any(inside(pt, h) for h in poly[1:])
               for poly in geojson["coordinates"])


def main():
    districts = build_districts()
    with open(B("out", "aed.json"), encoding="utf-8") as f:
        aeds = json.load(f)
    out, fallback = {}, 0
    for a in aeds:
        pt = (a["lon"], a["lat"])
        hit = [d["name"] for d in districts if contains(d["geojson"], pt)]
        if not hit:
            fallback += 1
            hit = [min(districts, key=lambda d: min((x - pt[0]) ** 2 + (y - pt[1]) ** 2
                                                    for poly in d["geojson"]["coordinates"] for x, y in poly[0]))["name"]]
        out[str(a["id"])] = hit[0]
    with open(B("out", "aed_district.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=0, sort_keys=True)
    log(f"{len(out)} AEDs in {len(set(out.values()))} districts, {fallback} assigned to the nearest")


if __name__ == "__main__":
    main()

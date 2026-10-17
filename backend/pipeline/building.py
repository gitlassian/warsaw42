"""Match AED coordinates to building footprints (city GeoServer layer `budynki`).

    python -m pipeline.building [--footprints data/geo/budynki.geojson]

Writes data/out/aed_building.json: {id: {in_footprint, dist_m, building_floors, building_type, building_id}}.
`in_footprint` is True when the point lies inside a footprint; otherwise the nearest footprint within
NEAR_M metres is reported (AED coordinates are often placed on the facade or the pavement).
The footprints file is large and not committed, so this step is run by hand, not by the refresh job.
"""
import argparse
import json
import math
import os
from collections import defaultdict

ROOT = os.path.join(os.path.dirname(__file__), "..", "data")
NEAR_M = 15.0
CELL = 0.001  # grid cell in degrees (~110 m x 70 m)
KX, KY = 111320 * math.cos(math.radians(52.23)), 110540  # metres per degree at Warsaw


def _rings(geom):
    polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    return polys  # list of polygons; each polygon = [outer ring, *holes]


def _inside(x, y, ring):
    c = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i][:2]
        xj, yj = ring[j][:2]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            c = not c
        j = i
    return c


def _seg_dist_m(px, py, ax, ay, bx, by):
    ax, ay, bx, by, px, py = ax * KX, ay * KY, bx * KX, by * KY, px * KX, py * KY
    dx, dy = bx - ax, by - ay
    t = 0 if dx == dy == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def match(points, features):
    grid = defaultdict(list)
    for f in features:
        if not f.get("geometry"):
            continue
        xs, ys = [], []
        for poly in _rings(f["geometry"]):
            for x, y, *_ in poly[0]:
                xs.append(x)
                ys.append(y)
        for gx in range(int(min(xs) / CELL), int(max(xs) / CELL) + 1):
            for gy in range(int(min(ys) / CELL), int(max(ys) / CELL) + 1):
                grid[(gx, gy)].append(f)
    out = {}
    for pid, (x, y) in points.items():
        cand = {id(f): f for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                for f in grid.get((int(x / CELL) + dx, int(y / CELL) + dy), [])}
        best, best_d, inside = None, 1e9, False
        for f in cand.values():
            d = 1e9
            for poly in _rings(f["geometry"]):
                if _inside(x, y, poly[0]) and not any(_inside(x, y, h) for h in poly[1:]):
                    d = 0.0
                    break
                for ring in poly:
                    d = min(d, min(_seg_dist_m(x, y, *ring[i][:2], *ring[i + 1][:2]) for i in range(len(ring) - 1)))
            if d < best_d:
                best, best_d, inside = f, d, d == 0.0
        if best is not None and best_d <= NEAR_M:
            p = best["properties"]
            out[pid] = {"in_footprint": inside, "dist_m": round(best_d, 1),
                        "building_floors": p.get("KONDYGNACJE_NADZIEMNE"),
                        "building_type": p.get("RODZAJ"), "building_id": p.get("ID_BUDYNKU")}
        else:
            out[pid] = {"in_footprint": False, "dist_m": None, "building_floors": None,
                        "building_type": None, "building_id": None}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--footprints", default=os.path.join(ROOT, "geo", "budynki.geojson"))
    ap.add_argument("--aed", default=os.path.join(ROOT, "raw", "scb_aed_list.json"))
    ap.add_argument("--out", default=os.path.join(ROOT, "out", "aed_building.json"))
    a = ap.parse_args()
    with open(a.aed, encoding="utf-8") as f:
        pts = {r["properties"]["defibrillator_id"]: tuple(r["geometry"]["coordinates"][0][:2]) for r in json.load(f)}
    with open(a.footprints, encoding="utf-8") as f:
        feats = json.load(f)["features"]
    res = match(pts, feats)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False, indent=1)
    print(len(res), "AEDs ->", a.out, "| inside a footprint:", sum(v["in_footprint"] for v in res.values()),
          "| within", NEAR_M, "m:", sum(v["dist_m"] is not None for v in res.values()))


if __name__ == "__main__":
    main()

"""Population density at building level: the GUS 1 km census grid spread over residential buildings.

    python3 -m pipeline.density

Reads  data/population/GRID_NSP2021_RES (GUS 2021, 1 km cells) and data/geo/budynki.geojson (city building layer),
       both in the repo-root data/ folder, not committed
Writes backend/data/out/population_100m.json: residents per 100 m cell, [lon, lat, residents, residents_65_plus]

Each census cell's residents are split over the residential buildings (RODZAJ = m) inside it in proportion to
footprint area x number of floors, so the totals of every cell stay exactly as GUS published them. A cell without
residential buildings falls back to all its buildings. GUS masks small counts, those cells count as empty, and a
masked 65+ count uses the city-wide share.
"""
import json
import math
import re
from collections import defaultdict

from pipeline.seed import B, H, laea_inverse, log, read_dbf

KY = 110540
CELL_M = 100


def laea_forward(lon, lat):
    """ETRS89-LAEA (EPSG:3035), the inverse of pipeline.seed.laea_inverse."""
    a, e2 = 6378137.0, 0.00669438002290
    e = math.sqrt(e2)
    phi0, lam0, FE, FN = math.radians(52), math.radians(10), 4321000.0, 3210000.0
    qf = lambda s: (1 - e2) * (s / (1 - e2 * s * s) - (1 / (2 * e)) * math.log((1 - e * s) / (1 + e * s)))
    qp, q0 = qf(1.0), qf(math.sin(phi0))
    beta0 = math.asin(q0 / qp)
    Rq = a * math.sqrt(qp / 2)
    D = a * math.cos(phi0) / math.sqrt(1 - e2 * math.sin(phi0) ** 2) / (Rq * math.cos(beta0))
    phi, lam = math.radians(lat), math.radians(lon)
    beta = math.asin(qf(math.sin(phi)) / qp)
    B_ = Rq * math.sqrt(2 / (1 + math.sin(beta0) * math.sin(beta) + math.cos(beta0) * math.cos(beta) * math.cos(lam - lam0)))
    x = B_ * D * math.cos(beta) * math.sin(lam - lam0)
    y = (B_ / D) * (math.cos(beta0) * math.sin(beta) - math.sin(beta0) * math.cos(beta) * math.cos(lam - lam0))
    return FE + x, FN + y


def footprint(geometry):
    """Centroid (lon, lat) and area (m2) of the outer rings of a MultiPolygon."""
    area, lons, lats = 0.0, [], []
    for poly in geometry["coordinates"]:
        ring = poly[0]
        kx = 111320 * math.cos(math.radians(ring[0][1]))
        s = 0.0
        for (x1, y1), (x2, y2) in zip(ring, ring[1:]):
            s += (x1 * kx) * (y2 * KY) - (x2 * kx) * (y1 * KY)
        area += abs(s) / 2
        lons += [p[0] for p in ring[:-1]]
        lats += [p[1] for p in ring[:-1]]
    return sum(lons) / len(lons), sum(lats) / len(lats), area


def main():
    num = lambda v: int(v) if v.isdigit() else None  # masked counts ("*****") are not zero, they are unknown
    cells = {}
    for r in read_dbf(H("population", "GRID_NSP2021_RES", "GRID_NSP2021_RES.dbf")):
        m = re.match(r"CRS3035RES1000mN(\d+)E(\d+)", r["CODE"])
        if not m or not (num(r["RES"]) or 0):
            continue
        n, e = int(m.group(1)), int(m.group(2))
        lon, lat = laea_inverse(e + 500, n + 500)
        if 20.8 < lon < 21.3 and 52.0 < lat < 52.4:
            cells[(e, n)] = (num(r["RES"]), num(r["RES_65_"]))
    total = sum(v[0] for v in cells.values())
    known = [(v[0], v[1]) for v in cells.values() if v[1] is not None]
    share65 = sum(b for _, b in known) / sum(a for a, _ in known)
    log(f"{len(cells)} census cells with residents near Warsaw, {total} residents, 65+ share {share65:.3f}")

    log("reading buildings ...")
    with open(H("geo", "budynki.geojson"), encoding="utf-8") as f:
        features = json.load(f)["features"]
    residential, other = defaultdict(list), defaultdict(list)
    for f_ in features:
        p = f_["properties"]
        if not f_.get("geometry"):
            continue
        lon, lat, area = footprint(f_["geometry"])
        e, n = laea_forward(lon, lat)
        key = (int(e // 1000) * 1000, int(n // 1000) * 1000)
        if key not in cells:
            continue
        weight = area * min(max(p.get("KONDYGNACJE_NADZIEMNE") or 1, 1), 40)
        (residential if p["RODZAJ"] == "m" else other)[key].append((e, n, weight))

    grid = defaultdict(lambda: [0.0, 0.0])  # (E//100, N//100) -> residents, residents 65+
    placed = unplaced = 0
    for key, (res, res65) in cells.items():
        buildings = residential.get(key) or other.get(key)
        if not buildings:
            unplaced += res
            continue
        share = (res65 / res) if res65 is not None else share65
        norm = sum(w for _, _, w in buildings)
        for e, n, w in buildings:
            part = res * w / norm
            cell = grid[(int(e // CELL_M), int(n // CELL_M))]
            cell[0] += part
            cell[1] += part * share
        placed += res
    out = []
    for (ge, gn), (res, res65) in sorted(grid.items()):
        lon, lat = laea_inverse(ge * CELL_M + CELL_M / 2, gn * CELL_M + CELL_M / 2)
        out.append([round(lon, 5), round(lat, 5), round(res, 2), round(res65, 2)])
    with open(B("out", "population_100m.json"), "w", encoding="utf-8") as f:
        json.dump({"cell_m": CELL_M, "source": "GUS NSP 2021 1 km grid spread over residential buildings (m.st. Warszawa building layer)",
                   "residents": round(placed), "cells": out}, f, separators=(",", ":"))
    log(f"{len(out)} cells of {CELL_M} m, {placed} residents placed, {unplaced} in cells without any building")


if __name__ == "__main__":
    main()

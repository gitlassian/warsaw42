"""Where a new AED helps most, for every half hour of the week: greedy maximum coverage of residents.

    python3 -m pipeline.placement [--radius 500]

Reads  data/out/population_100m.json (pipeline.density), aed.json, scb_aed_list.json, aed_osm_hours.json, osm_extra.json,
       data/geo/punkty_adresowe.geojson (repo-root data/, not committed: candidate addresses)
Writes data/out/placement.json, which seed_sql puts in app_data under the key `placement`.

For each of the 336 half-hour slots of a week it counts the residents living within `radius` of an AED that is open
(verified hours) at that moment, then ranks 20 steps of two kinds:
  new      addresses where a new AED would add the most residents
  convert  public AEDs that are closed at that moment; making them reachable around the clock (outdoor cabinet)
           would add the most residents, with no purchase needed
Coverage is straight-line distance and residents are spread over residential buildings: an estimate for prioritising.
Slots are indexed day * 48 + minute / 30, Monday = day 0.
"""
import argparse
import json
import math
import os
import re

import numpy as np
from scipy.sparse import csr_matrix
from scipy.spatial import cKDTree

from pipeline.osm_match import street_label
from pipeline.seed import B, H, log
from pipeline.seed_sql import DAYS, combine, review

KY = 110540
KX = 111320 * math.cos(math.radians(52.23))
STEPS = 20
SLOT_MIN = 30
DAY_KEYS = list(DAYS)
# One-AED budget projects (BO 2019-2025): 7.2, 7.5, 7.9, 12.0, 13.0 and 14.9 thousand PLN, median about 10 thousand.
COST_PER_AED_PLN = 10_000
COST_BASIS = "mediana jednostkowych projektów AED w Budżecie Obywatelskim 2019–2025 (7,2–14,9 tys. zł)"


def to_m(lon, lat):
    return (lon - 20.7) * KX, (lat - 52.0) * KY


def active_at(c, day, minute):
    """The AED has verified hours that include this moment."""
    if not c["verified"]:
        return False
    if c["status"] == "24/7":
        return True
    return c["status"] == "scheduled" and any(
        int(a[:2]) * 60 + int(a[3:]) <= minute < int(b[:2]) * 60 + int(b[3:]) for a, b in c["schedule"][day]
    )


def existing_aeds():
    with open(B("raw", "scb_aed_list.json"), encoding="utf-8") as f:
        raw = json.load(f)
    with open(B("out", "aed.json"), encoding="utf-8") as f:
        parsed = {r["id"]: r for r in json.load(f)}
    with open(B("out", "aed_osm_hours.json"), encoding="utf-8") as f:
        osm = json.load(f)
    out = []
    for item in raw:
        p = item["properties"]
        r = parsed[p["defibrillator_id"]]
        c = combine(r, review(r, False)[0], osm.get(str(p["defibrillator_id"])))
        out.append({"id": str(p["defibrillator_id"]), "name": p["location_object_name"],
                    "address": f"{p['location_street'].strip()} {p['location_building'].strip()}",
                    "lon": r["lon"], "lat": r["lat"], "public": bool(r["public"]), **c})
    with open(B("out", "osm_extra.json"), encoding="utf-8") as f:
        for x in json.load(f):
            ok = x["status"] != "unknown"
            out.append({"id": f"osm:{x['osm_id']}", "name": x["name"], "address": x["address"], "lon": x["lon"], "lat": x["lat"],
                        "public": True, "status": x["status"], "schedule": x["schedule"], "verified": ok})
    return out


def sparse(reach, n_cols):
    indptr = np.cumsum([0] + [len(r) for r in reach])
    indices = np.fromiter((i for r in reach for i in r), dtype=np.int64, count=int(indptr[-1]))
    return csr_matrix((np.ones(len(indices), dtype=np.float32), indices, indptr), shape=(len(reach), n_cols))


def greedy(matrix, weights, weights65, covered, steps):
    """Max coverage: each step takes the site that adds the most uncovered residents. matrix[j] = cells site j covers."""
    covered = covered.copy()
    total = weights.sum()
    cum = float(weights[covered].sum())
    picks = []
    for _ in range(steps):
        gains = matrix @ (weights * ~covered)
        j = int(np.argmax(gains))
        if gains[j] <= 0:
            break
        cells = matrix[j].indices
        new = cells[~covered[cells]]
        cum += float(weights[new].sum())
        picks.append([j, round(float(weights[new].sum())), round(float(weights65[new].sum())), round(100 * cum / total, 1)])
        covered[new] = True
    return picks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--radius", type=int, default=500)
    radius = ap.parse_args().radius

    with open(B("out", "population_100m.json"), encoding="utf-8") as f:
        pop = json.load(f)
    cells = pop["cells"]
    lon, lat = np.array([c[0] for c in cells]), np.array([c[1] for c in cells])
    X, Y = to_m(lon, lat)
    W, W65 = np.array([c[2] for c in cells]), np.array([c[3] for c in cells])
    total = float(W.sum())
    demand = cKDTree(np.column_stack([X, Y]))
    log(f"{len(cells)} demand cells, {total:.0f} residents")

    log("candidate addresses ...")
    with open(H("geo", "punkty_adresowe.geojson"), encoding="utf-8") as f:
        points = json.load(f)["features"]
    best = {}
    for p in points:
        if not p.get("geometry"):
            continue
        lo, la = p["geometry"]["coordinates"]
        x, y = to_m(lo, la)
        key = (int(x // 100), int(y // 100))
        d = math.hypot(x - (key[0] * 100 + 50), y - (key[1] * 100 + 50))
        if key not in best or d < best[key][0]:
            a = p["properties"]
            best[key] = (d, x, y, lo, la, f"{street_label(a['NAZWA_ULICY'])} {a['NUMER_PORZADKOWY']}, {a['KOD_POCZTOWY']} Warszawa")
    cand = list(best.values())
    new_matrix = sparse(demand.query_ball_point(np.array([[c[1], c[2]] for c in cand]), r=radius), len(cells))
    log(f"{len(cand)} candidate addresses")

    aeds = existing_aeds()
    public = np.array([a["public"] for a in aeds])
    verified = np.array([a["verified"] for a in aeds])
    aed_matrix = sparse(demand.query_ball_point(np.array([to_m(a["lon"], a["lat"]) for a in aeds]), r=radius), len(cells))

    used_cand, used_aed, slots, cache = {}, {}, [], {}
    ref = lambda table, key: table.setdefault(key, len(table))
    for day, dkey in enumerate(DAY_KEYS):
        for minute in range(0, 24 * 60, SLOT_MIN):
            active = np.array([bool(a["public"] and active_at(a, dkey, minute)) for a in aeds])
            sig = active.tobytes()
            if sig not in cache:
                covered = (aed_matrix.T @ active.astype(np.float32)) > 0
                new = greedy(new_matrix, W, W65, covered, STEPS)
                closed = np.flatnonzero(public & verified & ~active)
                conv = greedy(aed_matrix[closed], W, W65, covered, STEPS) if len(closed) else []
                cache[sig] = {
                    "a": int(active.sum()), "c": round(100 * float(W[covered].sum()) / total, 1),
                    "u": round(float(W[~covered].sum())), "u65": round(float(W65[~covered].sum())),
                    "n": [[ref(used_cand, p[0]), *p[1:]] for p in new],
                    "v": [[ref(used_aed, int(closed[p[0]])), *p[1:]] for p in conv],
                }
            slots.append(cache[sig])
    log(f"{len(cache)} distinct open-AED sets across {len(slots)} slots")
    out = {"radius_m": radius, "slot_minutes": SLOT_MIN, "cost_per_aed_pln": COST_PER_AED_PLN, "cost_basis": COST_BASIS,
           "residents": round(total), "population_source": pop["source"],
           "candidates": [[round(cand[j][3], 6), round(cand[j][4], 6), cand[j][5]] for j in used_cand],
           "aeds": [[aeds[j]["id"], aeds[j]["name"], aeds[j]["address"], round(aeds[j]["lon"], 6), round(aeds[j]["lat"], 6)] for j in used_aed],
           "slots": slots}
    with open(B("out", "placement.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    night, day = slots[1 * 48 + 6], slots[1 * 48 + 28]
    log(f"Tue 03:00: {night['a']} open AEDs, {night['c']}% of residents covered, 10 new -> {night['n'][9][3]}%, 10 converted -> {night['v'][9][3]}%")
    log(f"Tue 14:00: {day['a']} open AEDs, {day['c']}% covered, 10 new -> {day['n'][9][3]}%, 10 converted -> {day['v'][9][3]}%")


if __name__ == "__main__":
    main()

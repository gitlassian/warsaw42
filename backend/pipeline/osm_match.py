"""Match OpenStreetMap AEDs to the city list.

    python3 -m pipeline.osm_match

Reads  data/aed/osm_aed_warszawa.json, data/geo/punkty_adresowe.geojson, data/geo/osm_dzielnice_raw.json (repo-root data/,
       not committed) and backend/data/out/aed.json
Writes data/out/aed_osm_hours.json  hours for city AEDs: {source_id: {...}} for an OSM node within 30 m with parseable hours
       data/out/osm_extra.json      public OSM AEDs that the city list lacks (more than 50 m from every city AED)

Only access=yes|permissive nodes become extra AEDs: customers/private/permit points are not open to a passer-by.
Their address comes from the nearest official address point within 60 m, then from addr:* tags.
"""
import json
import math
import os
import re
from collections import defaultdict

from pipeline import osm_hours
from pipeline.districts import contains
from pipeline.seed import B, H, build_districts, log

SAME_M = 30  # an OSM node this close is taken to be the same device
NEW_M = 50  # farther than this from every city AED: a device the city list lacks
ADDRESS_M = 60
DUP_M = 10
KX = 111320 * math.cos(math.radians(52.23))
KY = 110540


def dist(a, b):
    return math.hypot((a[0] - b[0]) * KY, (a[1] - b[1]) * KX)


class Grid:
    """Cell index so that nearest-neighbour lookups stay cheap for 127k address points."""

    def __init__(self, items, cell_m=100):
        self.cell = (cell_m / KY, cell_m / KX)
        self.cells = defaultdict(list)
        for it in items:
            self.cells[self.key(it[0])].append(it)

    def key(self, p):
        return (int(p[0] / self.cell[0]), int(p[1] / self.cell[1]))

    def nearest(self, p, max_m):
        ky, kx = self.key(p)
        reach = int(max_m / 100) + 1
        best = None
        for dy in range(-reach, reach + 1):
            for dx in range(-reach, reach + 1):
                for it in self.cells.get((ky + dy, kx + dx), ()):
                    d = dist(p, it[0])
                    if d <= max_m and (best is None or d < best[0]):
                        best = (d, it)
        return best


def point(e):
    return (e["lat"], e["lon"]) if "lat" in e else (e["center"]["lat"], e["center"]["lon"])


def street_label(name):
    name = re.sub(r"^ulica\s+", "", name or "")
    for long, short in (("aleja ", "al. "), ("aleje ", "al. "), ("plac ", "pl. "), ("rondo ", "rondo "), ("osiedle ", "os. ")):
        if name.lower().startswith(long):
            return short + name[len(long):]
    return name


def level_of(tags):
    try:
        v = float(tags.get("level", ""))
    except ValueError:
        return None
    return int(v) if v == int(v) and -5 <= v <= 60 else None


def main():
    with open(H("aed", "osm_aed_warszawa.json"), encoding="utf-8") as f:
        nodes = json.load(f)["elements"]
    with open(B("out", "aed.json"), encoding="utf-8") as f:
        city = json.load(f)
    city_grid = Grid([((c["lat"], c["lon"]), c) for c in city])

    # 1. hours for city AEDs
    hours = {}
    for e in nodes:
        t = e.get("tags", {})
        if "opening_hours" not in t:
            continue
        hit = city_grid.nearest(point(e), SAME_M)
        parsed = osm_hours.parse(t["opening_hours"]) if hit else None
        if not parsed:
            continue
        d, (_, c) = hit
        if c["id"] in hours and hours[c["id"]]["dist_m"] <= d:
            continue
        hours[c["id"]] = {"osm_id": e["id"], "dist_m": round(d, 1), "opening_hours": t["opening_hours"],
                          "status": parsed.status, "schedule": parsed.schedule, "check_date": t.get("check_date")}
    with open(B("out", "aed_osm_hours.json"), "w", encoding="utf-8") as f:
        json.dump(hours, f, ensure_ascii=False, indent=0, sort_keys=True)

    # 2. public AEDs the city list lacks
    log("reading address points ...")
    with open(H("geo", "punkty_adresowe.geojson"), encoding="utf-8") as f:
        addr = Grid([((p["geometry"]["coordinates"][1], p["geometry"]["coordinates"][0]), p["properties"])
                     for p in json.load(f)["features"] if p.get("geometry")])
    districts = build_districts()
    extra, taken = [], []
    for e in sorted(nodes, key=lambda n: n["id"]):
        t = e.get("tags", {})
        p = point(e)
        if t.get("access") not in ("yes", "permissive") or city_grid.nearest(p, NEW_M):
            continue
        if any(dist(p, q) <= DUP_M for q in taken):
            continue
        taken.append(p)
        hit = addr.nearest(p, ADDRESS_M)
        if hit:
            a = hit[1][1]
            address = f"{street_label(a['NAZWA_ULICY'])} {a['NUMER_PORZADKOWY']}, {a['KOD_POCZTOWY']} Warszawa"
        elif t.get("addr:street"):
            address = f"{t['addr:street']} {t.get('addr:housenumber', '')}".strip() + ", Warszawa"
        else:
            address = "Warszawa (adres nieznany)"
        district = next((d["name"] for d in districts if contains(d["geojson"], (p[1], p[0]))), None)
        parsed = osm_hours.parse(t.get("opening_hours"))
        place = t.get("defibrillator:location:pl") or t.get("defibrillator:location") or t.get("description:pl") or t.get("description")
        extra.append({
            "osm_id": e["id"], "lat": p[0], "lon": p[1], "name": t.get("name") or t.get("operator") or "Defibrylator (OpenStreetMap)",
            "address": address, "district": district, "indoor": t.get("indoor") == "yes", "floor": level_of(t),
            "location": place, "opening_hours": t.get("opening_hours"), "check_date": t.get("check_date"),
            "status": parsed.status if parsed else "unknown", "schedule": parsed.schedule if parsed else None,
        })
    with open(B("out", "osm_extra.json"), "w", encoding="utf-8") as f:
        json.dump(extra, f, ensure_ascii=False, indent=0)
    log(f"hours for {len(hours)} city AEDs; {len(extra)} extra public OSM AEDs "
        f"({sum(1 for x in extra if x['status'] != 'unknown')} with parseable hours, {sum(1 for x in extra if x['district'] is None)} outside the districts)")


if __name__ == "__main__":
    main()

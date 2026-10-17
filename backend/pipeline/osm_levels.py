"""Fetch OSM defibrillators that carry a `level` tag (a few KB) -> data/raw/osm_levels.json.

    python -m pipeline.osm_levels

Used by build.py as a second source of the AED floor. Data (c) OpenStreetMap contributors, ODbL.
"""
import json
import os
import re
import time
import urllib.parse
import urllib.request

OUT = os.path.join(os.path.dirname(__file__), "..", "data", "raw", "osm_levels.json")
QUERY = ('[out:json][timeout:120];area["name"="Warszawa"]["boundary"="administrative"]->.a;'
         '(node["emergency"="defibrillator"]["level"](area.a););out tags center;')
ENDPOINTS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]


def main():
    data = None
    for attempt in range(3):  # Overpass is often overloaded: retry, rotating endpoints
        ep = ENDPOINTS[attempt % len(ENDPOINTS)]
        try:
            req = urllib.request.Request(ep, data=urllib.parse.urlencode({"data": QUERY}).encode(),
                                         headers={"User-Agent": "warsaw42-aed/0.1"})
            data = json.loads(urllib.request.urlopen(req, timeout=180).read())
            break
        except Exception as e:
            print("overpass failed", ep, repr(e)[:100])
            time.sleep(5 * (attempt + 1))
    if data is None:
        raise SystemExit("no Overpass endpoint answered; keeping the old file")
    out = []
    for e in data["elements"]:
        lv = e.get("tags", {}).get("level", "").strip()
        if re.fullmatch(r"-?\d{1,2}", lv):  # skip ranges like "0;1"
            out.append({"lon": e["lon"], "lat": e["lat"], "level": int(lv)})
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f)
    print(len(out), "OSM AEDs with a numeric level ->", OUT)


if __name__ == "__main__":
    main()

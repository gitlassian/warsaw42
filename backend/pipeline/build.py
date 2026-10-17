"""Build data/out/aed.json (the contract from PLAN.md) from the raw SCB snapshot.

    python -m pipeline.build [--in data/raw/scb_aed_list.json] [--out data/out/aed.json] [--no-llm]

Status logic, in order:
  1. device_availability == "Tak"  -> 24/7 (empty hours text is normal here)
  2. hours text parsed by regex     -> scheduled
  3. otherwise LLM fallback (cached) -> scheduled | 24/7 | unknown
Records the pipeline cannot trust stay "unknown" and are drawn grey on the map.
"""
import argparse
import json
import os
import re
from collections import Counter

import math

from . import llm_hours
from .floor import floor_from_text
from .hours import Parsed, empty_schedule, full_schedule, parse_regex, to_osm, DAY_KEYS

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "data")
# 24/7 + indoors is plausible at places with round-the-clock security; the rest is worth a second look
STAFFED_24H = re.compile(r"urz[ąa]d dzielnicy|stra[żz] miejska|policj|komend|szpital|dworzec|lotnisko|metro", re.I)


def hours_text(p):
    """The hours string, tolerating records where the text ended up in device_availability."""
    desc = (p.get("device_access_description") or "").strip()
    if desc:
        return desc
    av = (p.get("device_availability") or "").strip()
    if av not in ("Tak", "Nie", "Ograniczona", "") and re.search(r"\d", av):
        return av
    m = re.match(r"Nie\s*\((.*)\)", av)
    return m.group(1) if m else ""


OSM_MAX_M = 30  # an OSM AED this close with a numeric `level` is taken as the same device


def _load(name):
    try:
        with open(os.path.join(ROOT, *name), encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return None


def _osm_index():
    pts = _load(("raw", "osm_levels.json")) or []
    kx = 111320 * math.cos(math.radians(52.23))
    return [(p["lon"] * kx, p["lat"] * 110540, p["level"]) for p in pts], kx


def _osm_level(lon, lat, osm, kx):
    best = min(((math.hypot(lon * kx - x, lat * 110540 - y), lv) for x, y, lv in osm), default=(1e9, None))
    return best[1] if best[0] <= OSM_MAX_M else None


def build(records, cache, use_llm=True):
    out, stats = [], Counter()
    buildings = _load(("out", "aed_building.json")) or {}  # optional, made by pipeline.building
    osm, kx = _osm_index()
    for rec in records:
        p = rec["properties"]
        lon, lat = rec["geometry"]["coordinates"][0][:2]
        raw = hours_text(p)
        avail = (p.get("device_availability") or "").strip()
        suspicious = []
        if avail == "Tak":
            parsed = Parsed("24/7", full_schedule(), source="availability_field")
            if raw and re.search(r"\d\s*[-–]\s*\d", raw):
                suspicious.append("24/7 flag but the text lists limited hours")
        else:
            parsed = parse_regex(raw) if raw else None
            if parsed is None:
                parsed = llm_hours.resolve(raw, cache, enabled=use_llm) if raw else Parsed(
                    "unknown", empty_schedule(), source="no_text", note="no hours given")
        indoor = "zewn" not in (p.get("device_location") or "").lower()
        name = p.get("location_object_name") or ""
        if parsed.status == "24/7" and indoor and not STAFFED_24H.search(name) and avail == "Tak":
            suspicious.append("24/7 indoors outside a staffed building")
        stats[parsed.source.split(":")[0] + "/" + parsed.status] += 1
        floor = floor_from_text(p.get("location_description"))
        floor_source = "text" if floor is not None else None
        if floor is None and osm:
            floor = _osm_level(lon, lat, osm, kx)
            floor_source = "osm" if floor is not None else None
        stats["floor/" + (floor_source or "none")] += 1
        b = buildings.get(p["defibrillator_id"], {})
        out.append({
            "id": p["defibrillator_id"], "lon": lon, "lat": lat, "name": name,
            "street": " ".join(x for x in [p.get("location_street"), p.get("location_building")] if x),
            "indoor": indoor, "in_building": indoor,  # SCB field `device_location`; "outdoor" can still mean an external staircase
            "floor": floor, "floor_source": floor_source,  # 0 = ground, -1 = basement; null = unknown
            "in_footprint": b.get("in_footprint"), "building_floors": b.get("building_floors"),
            "building_type": b.get("building_type"), "location_description": p.get("location_description"),
            "public": p.get("device_public_access") == "Publiczny",
            "status": parsed.status, "schedule": parsed.schedule,
            "osm_hours": to_osm(parsed.schedule) if parsed.status != "unknown" else None,
            "raw_hours": raw or None, "parse_source": parsed.source, "assumed": parsed.assumed,
            "note": parsed.note or None,
            "suspicious": bool(suspicious), "suspicious_reasons": suspicious,
        })
    return out, stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", default=os.path.join(ROOT, "raw", "scb_aed_list.json"))
    ap.add_argument("--out", default=os.path.join(ROOT, "out", "aed.json"))
    ap.add_argument("--no-llm", action="store_true")
    a = ap.parse_args()
    with open(a.src, encoding="utf-8") as f:
        records = json.load(f)
    cache = llm_hours.load_cache()
    out, stats = build(records, cache, use_llm=not a.no_llm)
    llm_hours.save_cache(cache)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(len(out), "AEDs ->", a.out)
    for k, v in sorted(stats.items(), key=lambda kv: -kv[1]):
        print(f"  {k:32s} {v}")
    print("  suspicious:", sum(r["suspicious"] for r in out))


if __name__ == "__main__":
    main()

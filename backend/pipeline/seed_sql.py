"""Write supabase/seed.sql: the AED snapshot as SQL for the schema in supabase/migrations.

    python -m pipeline.seed_sql [--out supabase/seed.sql] [--trust-flagged-247]

Inputs: data/raw/scb_aed_list.json (addresses, raw fields), data/out/aed.json (parsed hours,
floors) and data/raw/warsaw_boundary.geojson (service area),
data/out/aed_district.json (pipeline.districts), data/out/aed_photos.json (pipeline.photos),
data/out/aed_osm_hours.json and data/out/osm_extra.json (pipeline.osm_match), all optional. The seed expects an empty database.

Hours are trusted (`hours_verified = true`) only when the pipeline did not
guess. LLM schedules, assumed weekdays and flagged 24/7-indoors records remain unverified, so the
API reports their hours as unknown until someone checks them. A day with no intervals is stored
as unknown when the text names no days (assumed weekdays or metro hours) and as closed when it does:
"poniedziałek-piątek 8-16" means the weekend is closed.
"""
import argparse
import json
import os
from datetime import date, timedelta

ROOT = os.path.join(os.path.dirname(__file__), "..", "data")
DEFAULT_OUT = os.path.join(os.path.dirname(__file__), "..", "supabase", "seed.sql")
PARSER_VERSION = "pipeline@2026-10-17"
DAYS = {"mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6, "sun": 7}
FLAG_CODES = {
    "24/7 indoors outside a staffed building": "247_indoors_unstaffed",
    "24/7 flag but the text lists limited hours": "247_but_limited_text",
}


def q(v):
    """SQL literal."""
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, (dict, list)):
        return q(json.dumps(v, ensure_ascii=False)) + "::jsonb"
    return "'" + str(v).replace("\r\n", "\n").replace("'", "''") + "'"


def q_array(items):
    return "ARRAY[" + ", ".join(q(i) for i in items) + "]::text[]" if items else "'{}'::text[]"


def minutes(hhmm):
    h, m = hhmm.split(":")
    return int(h) * 60 + int(m)


def weekly(schedule):
    """{"mon": [["08:00", "16:00"]], ...} -> {"1": [[480, 960]], ...}, overlapping intervals merged."""
    out = {}
    for key, dow in DAYS.items():
        merged = []
        for start, end in sorted((minutes(a), minutes(b)) for a, b in (schedule or {}).get(key, [])):
            if end <= start:
                continue
            if merged and start <= merged[-1][1]:
                merged[-1][1] = max(merged[-1][1], end)
            else:
                merged.append([start, end])
        out[str(dow)] = merged
    return out


def review(r, trust_flagged_247):
    """(review_status, applied_source_rules) for one aed.json record."""
    if r["status"] == "unknown":
        return "validated", []  # known to be unknown; the API reports unknown either way
    if r["parse_source"].startswith("llm:"):
        return "needs_review", []
    if r["status"] == "24/7":
        return ("needs_review" if r["suspicious"] and not trust_flagged_247 else "validated"), []
    if "weekdays_assumed" in r["assumed"]:
        return "needs_review", []
    rules = ["metro_hours@1"] if "metro_hours_assumed" in r["assumed"] else []
    has_unknown_day = any(not r["schedule"].get(k) for k in DAYS)
    return ("validated_partial" if has_unknown_day or rules else "validated"), rules


def easter(year):
    """Gregorian Easter Sunday (anonymous algorithm)."""
    a, b, c = year % 19, year // 100, year % 100
    d, e = b // 4, b % 4
    g = (8 * b + 13) // 25
    h = (19 * a + b - d - g + 15) % 30
    i, k = c // 4, c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 19 * l) // 433
    month = (h + l - 7 * m + 90) // 25
    return date(year, month, (h + l - 7 * m + 33 * month + 19) % 32)


def polish_holidays(year):
    e = easter(year)
    return [
        (date(year, 1, 1), "Nowy Rok"),
        (date(year, 1, 6), "Trzech Króli"),
        (e, "Wielkanoc"),
        (e + timedelta(days=1), "Poniedziałek Wielkanocny"),
        (date(year, 5, 1), "Święto Pracy"),
        (date(year, 5, 3), "Święto Konstytucji 3 Maja"),
        (e + timedelta(days=49), "Zielone Świątki"),
        (e + timedelta(days=60), "Boże Ciało"),
        (date(year, 8, 15), "Wniebowzięcie NMP"),
        (date(year, 11, 1), "Wszystkich Świętych"),
        (date(year, 11, 11), "Narodowe Święto Niepodległości"),
        (date(year, 12, 24), "Wigilia"),
        (date(year, 12, 25), "Boże Narodzenie"),
        (date(year, 12, 26), "Drugi dzień Bożego Narodzenia"),
    ]


def combine(r, review_status, osm):
    """Merge the city hours of one aed.json record with the OSM hours of the same device.

    -> {"status", "schedule" (day -> intervals, or None), "closed" (days OSM says are closed), "verified", "source"}
    City hours stay unless they are unusable (unknown, or a 24/7 flag that is not trusted) and OSM states hours.
    When OSM repeats every day the city lists, the two sources confirm each other, so the hours count as verified
    and the days the city leaves out are filled from OSM, where an unmentioned day is closed.
    """
    city_ok = review_status in ("validated", "validated_partial")
    # A text that names its days ("poniedziałek-piątek 8-16") says when the device is reachable, so the days it
    # leaves out are closed. Hours with an assumed weekday range or metro timetable name no days: those stay unknown.
    explicit = city_ok and r["status"] == "scheduled" and not r["assumed"]
    base = {"status": r["status"], "schedule": r["schedule"] if r["status"] == "scheduled" else None,
            "closed": {d for d in DAYS if not r["schedule"][d]} if explicit else set(), "verified": city_ok, "source": "city"}
    if not osm:
        return base
    sched = osm["schedule"]
    if r["status"] == "scheduled" and osm["status"] == "scheduled" and all(sched[d] == r["schedule"][d] for d in DAYS if r["schedule"][d]):
        return {"status": "scheduled", "schedule": {d: r["schedule"][d] or sched[d] for d in DAYS},
                "closed": {d for d in DAYS if not r["schedule"][d] and not sched[d]}, "verified": True, "source": "city_osm"}
    if r["status"] == "24/7" and osm["status"] == "24/7":
        return {**base, "verified": True, "source": "city_osm"}
    if not city_ok or r["status"] == "unknown":
        if r["status"] in ("unknown", "24/7"):  # no usable city hours at all: OSM is the only source
            return {"status": osm["status"], "schedule": sched if osm["status"] == "scheduled" else None,
                    "closed": {d for d in DAYS if not sched[d]} if osm["status"] == "scheduled" else set(),
                    "verified": True, "source": "osm"}
    return base


def hours_json(schedule, closed):
    """Database shape of the hours: a weekday with intervals is open, one OSM calls closed is closed, the rest is omitted (unknown)."""
    merged = weekly(schedule) if schedule else {}
    days = {}
    for key, dow in DAYS.items():
        if merged.get(str(dow)):
            days[str(dow)] = {"state": "open_intervals", "intervals": merged[str(dow)]}
        elif key in closed:
            days[str(dow)] = {"state": "closed", "intervals": []}
    return {"weekly": days, "exceptions": {}, "holiday_policy": "unknown"}


def seed_rows(raw, parsed, trust_flagged_247, osm=None):
    by_id = {r["id"]: r for r in parsed}
    osm = osm or {}
    rows = []
    for item in raw:
        p = item["properties"]
        r = by_id[p["defibrillator_id"]]
        status, rules = review(r, trust_flagged_247)
        flags = [FLAG_CODES[s] for s in r["suspicious_reasons"] if s in FLAG_CODES]
        if r["parse_source"].startswith("llm:"):
            flags.append("hours_llm")
        if r["status"] == "unknown":
            flags.append("hours_unknown")
        rows.append([
            p["defibrillator_id"], p["location_object_name"],
            p["location_street"].strip(), p["location_building"].strip(), p["location_postcode"], p["location_city"],
            r["lon"], r["lat"], r["in_building"], r.get("in_footprint"), r["floor"], r["floor_source"],
            p.get("location_description") or None,
            "public" if r["public"] else "restricted", p.get("device_public_access"),
            p.get("device_availability"), p.get("device_access_description") or None,
            p.get("device_manufacturer"), p.get("device_specifications"),
            r["status"], status, r["parse_source"], r["osm_hours"], rules, r["note"],
            weekly(r["schedule"]) if r["status"] == "scheduled" else None,
            flags, combine(r, status, osm.get(str(p["defibrillator_id"]))),
        ])
    return rows


def render(raw, parsed, boundary, trust_flagged_247=False, districts=None, photos=(), osm_hours=None, osm_extra=()):
    districts, photos = districts or {}, set(photos)
    values = []
    for r in seed_rows(raw, parsed, trust_flagged_247, osm_hours):
        c = r[-1]
        address = f"{r[2]} {r[3]}, {r[4]} {r[5]}"
        values.append("(" + ", ".join(q(v) for v in [
            r[0], r[1], address, r[6], r[7], r[8], r[10], r[12], r[13],
            r[16], c["status"], c["verified"], hours_json(c["schedule"], c["closed"]),
            f"{r[0]}.webp" if str(r[0]) in photos else None, districts.get(str(r[0])),
            "city", None if c["status"] == "unknown" else c["source"],
        ]) + ")")
    for x in osm_extra:  # public OSM devices the city list lacks, marked source = 'osm'
        scheduled = x["status"] == "scheduled"
        closed = {d for d in DAYS if not x["schedule"][d]} if scheduled else set()
        values.append("(" + ", ".join(q(v) for v in [
            f"osm:{x['osm_id']}", x["name"], x["address"], x["lon"], x["lat"], x["indoor"], x["floor"], x["location"],
            "public", x["opening_hours"], x["status"], x["status"] != "unknown",
            hours_json(x["schedule"] if scheduled else None, closed), None, x["district"],
            "osm", "osm" if x["status"] != "unknown" else None,
        ]) + ")")
    holidays = [h for y in (2026, 2027) for h in polish_holidays(y)]
    holiday_values = ",\n".join(f"({q(d.isoformat())}, {q(n)})" for d, n in holidays)
    aed_values = ",\n".join(values)
    return f"""-- Generated by python -m pipeline.seed_sql. Requires all migrations.
BEGIN;
SET LOCAL search_path = public, extensions;
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM aeds) THEN
        RAISE EXCEPTION 'seed expects an empty aeds table';
    END IF;
END $$;
INSERT INTO service_area (boundary, source)
VALUES (ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON({q(json.dumps(boundary["geometry"]))}), 4326)),
        {q(boundary["properties"]["source"])})
ON CONFLICT (id) DO UPDATE SET boundary = EXCLUDED.boundary, source = EXCLUDED.source, updated_at = now();
INSERT INTO public_holiday (on_date, name) VALUES
{holiday_values}
ON CONFLICT (on_date) DO NOTHING;
INSERT INTO aeds (source_id, object_name, full_address, lon, lat, in_building, floor,
    access_instructions, public_access, hours_text, hours_status, hours_verified, hours, photo_path, district,
    source, hours_source) VALUES
{aed_values};
INSERT INTO app_data (key, data) VALUES ('status',
    jsonb_build_object('aed_count', {len(values)}, 'osm_count', {len(osm_extra)}, 'source', 'Warsaw Open Data',
                       'attribution', 'Dane: m.st. Warszawa, SCB (CC BY)', 'updated_at', now()));
COMMIT;
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--trust-flagged-247", action="store_true",
                    help="treat 24/7 records flagged as indoors-unstaffed as validated")
    a = ap.parse_args()

    def load(*name):
        with open(os.path.join(ROOT, *name), encoding="utf-8") as f:
            return json.load(f)

    raw, parsed = load("raw", "scb_aed_list.json"), load("out", "aed.json")
    def optional(default, *name):
        return load(*name) if os.path.exists(os.path.join(ROOT, *name)) else default

    sql = render(raw, parsed, load("raw", "warsaw_boundary.geojson"), a.trust_flagged_247,
                 optional({}, "out", "aed_district.json"), optional([], "out", "aed_photos.json"),
                 optional({}, "out", "aed_osm_hours.json"), optional([], "out", "osm_extra.json"))
    with open(a.out, "w", encoding="utf-8") as f:
        f.write(sql)

    statuses = [review(r, a.trust_flagged_247)[0] for r in parsed]
    print(len(parsed), "AEDs ->", a.out)
    for s in sorted(set(statuses)):
        print(f"  {s:20s} {statuses.count(s)}")


if __name__ == "__main__":
    main()

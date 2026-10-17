"""Write supabase/seed.sql: the AED snapshot as SQL for the schema in supabase/migrations.

    python -m pipeline.seed_sql [--out supabase/seed.sql] [--trust-flagged-247]

Inputs: data/raw/scb_aed_list.json (addresses, raw fields), data/out/aed.json (parsed hours,
floors) and data/raw/warsaw_boundary.geojson (service area). The seed expects an empty database.

Hours are trusted (review_status validated / validated_partial) only when the pipeline did not
guess. LLM schedules, assumed weekdays and flagged 24/7-indoors records get needs_review, so the
API reports their hours as unknown until someone checks them. A day with no intervals is stored
as unknown, never closed: the source does not say which omitted days are closed.
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
    return "'" + str(v).replace("'", "''") + "'"


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


def seed_rows(raw, parsed, trust_flagged_247):
    by_id = {r["id"]: r for r in parsed}
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
            flags,
        ])
    return rows


SEED_COLUMNS = """
    source_id text, object_name text, street text, building_no text, postcode text, city text,
    lon double precision, lat double precision, in_building boolean, in_footprint boolean,
    floor smallint, floor_source floor_source, location_description text,
    public_access public_access, public_access_raw text, availability_raw text, access_text text,
    manufacturer text, has_specifications text,
    hours_status hours_status, review_status review_status, parse_source text, osm_hours text,
    applied_rules text[], note text, weekly jsonb, flags text[]"""

LOAD = f"""
INSERT INTO address (street_raw, building_no, postcode, city)
SELECT DISTINCT street, building_no, postcode, city FROM seed_aed
ON CONFLICT (street_raw, building_no, postcode) DO NOTHING;

INSERT INTO aed (source_id, object_name, address_id, lon, lat, in_building, in_footprint, floor, floor_source,
                 location_description, public_access, public_access_raw, availability_raw, access_text,
                 manufacturer, has_specifications)
SELECT s.source_id, s.object_name, ad.id, s.lon, s.lat, s.in_building, s.in_footprint, s.floor, s.floor_source,
       s.location_description, s.public_access, s.public_access_raw, s.availability_raw, s.access_text,
       s.manufacturer, s.has_specifications
FROM seed_aed s
JOIN address ad ON (ad.street_raw, ad.building_no, ad.postcode) = (s.street, s.building_no, s.postcode);

INSERT INTO aed_hours (aed_id, status, source_text, source_text_hash, osm_hours, applied_source_rules,
                       parse_source, parser_version, review_status, note)
SELECT a.id, s.hours_status, s.access_text, md5(coalesce(s.access_text, '')), s.osm_hours, s.applied_rules,
       s.parse_source, {q(PARSER_VERSION)}, s.review_status, s.note
FROM seed_aed s JOIN aed a ON a.source_id = s.source_id;

INSERT INTO aed_day_state (hours_id, dow, state)
SELECT h.id, d.key::smallint,
       CASE WHEN jsonb_array_length(d.value) > 0 THEN 'open_intervals'::day_state ELSE 'unknown'::day_state END
FROM seed_aed s
JOIN aed a ON a.source_id = s.source_id
JOIN aed_hours h ON h.aed_id = a.id AND h.origin = 'source'
CROSS JOIN LATERAL jsonb_each(s.weekly) d
WHERE s.weekly IS NOT NULL;

INSERT INTO aed_schedule (hours_id, dow, start_min, end_min)
SELECT h.id, d.key::smallint, (i->>0)::smallint, (i->>1)::smallint
FROM seed_aed s
JOIN aed a ON a.source_id = s.source_id
JOIN aed_hours h ON h.aed_id = a.id AND h.origin = 'source'
CROSS JOIN LATERAL jsonb_each(s.weekly) d
CROSS JOIN LATERAL jsonb_array_elements(d.value) i
WHERE s.weekly IS NOT NULL;

INSERT INTO audit_flag (aed_id, code, severity)
SELECT a.id, f.code, CASE WHEN f.code = 'hours_unknown' THEN 'info'::flag_severity ELSE 'warning'::flag_severity END
FROM seed_aed s JOIN aed a ON a.source_id = s.source_id
CROSS JOIN LATERAL unnest(s.flags) AS f(code);
"""


def render(raw, parsed, boundary, trust_flagged_247=False):
    rows = seed_rows(raw, parsed, trust_flagged_247)
    years = (2026, 2027)
    holidays = [h for y in years for h in polish_holidays(y)]
    values = ",\n".join(
        "(" + ", ".join(q_array(v) if i in (23, 26) else q(v) for i, v in enumerate(row)) + ")" for row in rows
    )
    return f"""-- Generated by `python -m pipeline.seed_sql`; do not edit by hand.
-- {len(rows)} AEDs from the Warsaw SCB snapshot. Expects an empty database (schema from supabase/migrations).
BEGIN;
SET LOCAL search_path = public, extensions;

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM aed) THEN
        RAISE EXCEPTION 'seed expects an empty aed table';
    END IF;
END $$;

INSERT INTO data_source (id, name, attribution, license_url) VALUES
    ('warsaw_open_data', 'Lokalizacje defibrylatorów AED (SCB)',
     'Dane: m.st. Warszawa, Stołeczne Centrum Bezpieczeństwa (CC BY)', 'https://creativecommons.org/licenses/by/4.0/'),
    ('osm_boundary', 'Granica m.st. Warszawy (OpenStreetMap)',
     '© OpenStreetMap contributors (ODbL)', 'https://opendatacommons.org/licenses/odbl/')
ON CONFLICT (id) DO NOTHING;

INSERT INTO service_area (boundary, source)
VALUES (ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON({q(json.dumps(boundary["geometry"]))}), 4326)),
        {q(boundary["properties"]["source"])})
ON CONFLICT (id) DO UPDATE SET boundary = EXCLUDED.boundary, source = EXCLUDED.source, updated_at = now();

INSERT INTO public_holiday (on_date, name) VALUES
{",\n".join(f"    ({q(d.isoformat())}, {q(n)})" for d, n in holidays)}
ON CONFLICT (on_date) DO NOTHING;

CREATE TEMP TABLE seed_aed ({SEED_COLUMNS}
) ON COMMIT DROP;

INSERT INTO seed_aed VALUES
{values};
{LOAD}
WITH run AS (
    INSERT INTO refresh_run (status, finished_at, total, added, removed, changed)
    VALUES ('ok', now(), {len(rows)}, {len(rows)}, 0, 0)
    RETURNING id
)
INSERT INTO dataset_version (cause, refresh_run_id) SELECT 'import', id FROM run;

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
    sql = render(raw, parsed, load("raw", "warsaw_boundary.geojson"), a.trust_flagged_247)
    with open(a.out, "w", encoding="utf-8") as f:
        f.write(sql)

    statuses = [review(r, a.trust_flagged_247)[0] for r in parsed]
    print(len(parsed), "AEDs ->", a.out)
    for s in sorted(set(statuses)):
        print(f"  {s:20s} {statuses.count(s)}")


if __name__ == "__main__":
    main()

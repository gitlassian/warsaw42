"""Structural checks for the hand-edited test fixtures in this folder.

Run from the repository root after editing any fixture:
    python3 fixtures/check_fixtures.py

Only the standard library is used. Exit code 1 means a fixture is malformed;
warnings (for example, a changed source record after a data refresh) do not fail the run.
"""

import json
import re
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"
RAW = ROOT / "backend/data/raw/scb_aed_list.json"

KINDS = {"weekly", "always_open", "unknown"}
DAY_STATES = {"open_intervals", "closed", "unknown"}
HOLIDAY = {"unknown", "closed", "regular_hours"}
REVIEW = {"pending", "validated", "validated_partial", "needs_review", "rejected"}
AVAILABILITY = {"open", "closed", "unknown"}
TIME = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$|^24:00$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

errors: list[str] = []
warnings: list[str] = []


def minutes(hhmm: str) -> int:
    h, m = hhmm.split(":")
    return int(h) * 60 + int(m)


def check_intervals(where: str, intervals) -> None:
    previous_end = -1
    for pair in intervals:
        if not (isinstance(pair, list) and len(pair) == 2 and all(isinstance(t, str) and TIME.match(t) for t in pair)):
            errors.append(f"{where}: interval {pair!r} must be [\"HH:MM\", \"HH:MM\"]")
            continue
        start, end = minutes(pair[0]), minutes(pair[1])
        if pair[0] == "24:00":
            errors.append(f"{where}: 24:00 may only close an interval")
        if end <= start:
            errors.append(f"{where}: {pair} ends before it starts; split overnight intervals across days")
        if start < previous_end:
            errors.append(f"{where}: {pair} overlaps or is out of order")
        previous_end = end


def check_day(where: str, day) -> None:
    if not isinstance(day, dict) or day.get("state") not in DAY_STATES:
        errors.append(f"{where}: state must be one of {sorted(DAY_STATES)}")
        return
    intervals = day.get("intervals", [])
    if day["state"] == "open_intervals":
        if not intervals:
            errors.append(f"{where}: open_intervals needs at least one interval")
        check_intervals(where, intervals)
    elif intervals:
        errors.append(f"{where}: {day['state']} must have empty intervals")


def check_schedule(where: str, s) -> None:
    if s.get("timezone") != "Europe/Warsaw":
        errors.append(f"{where}: timezone must be Europe/Warsaw")
    kind = s.get("kind")
    if kind not in KINDS:
        errors.append(f"{where}: kind must be one of {sorted(KINDS)}")
    if kind == "weekly":
        weekly = s.get("weekly") or {}
        if sorted(weekly) != [str(d) for d in range(1, 8)]:
            errors.append(f"{where}: weekly must list all ISO weekdays \"1\"..\"7\" (missing days are written as unknown)")
        for d, day in weekly.items():
            check_day(f"{where}.weekly.{d}", day)
    elif "weekly" in s:
        errors.append(f"{where}: only kind=weekly has a weekly table")
    if kind == "unknown" and s.get("review_status") in {"validated", "validated_partial"}:
        errors.append(f"{where}: unknown hours cannot be validated")
    for i, e in enumerate(s.get("date_exceptions", [])):
        if not DATE.match(str(e.get("date", ""))):
            errors.append(f"{where}.date_exceptions[{i}]: date must be YYYY-MM-DD")
        check_day(f"{where}.date_exceptions[{i}]", e)
    if s.get("holiday_policy") not in HOLIDAY:
        errors.append(f"{where}: holiday_policy must be one of {sorted(HOLIDAY)}")
    if s.get("review_status") not in REVIEW:
        errors.append(f"{where}: review_status must be one of {sorted(REVIEW)}")
    if not isinstance(s.get("access_conditions"), list):
        errors.append(f"{where}: access_conditions must be a list")


def unique(name: str, items, key: str) -> None:
    seen = set()
    for item in items:
        if item[key] in seen:
            errors.append(f"{name}: duplicate {key} {item[key]!r}")
        seen.add(item[key])


def load(name: str):
    try:
        return json.loads((FIXTURES / name).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as err:
        errors.append(f"{name}: cannot read JSON ({err})")
        return None


def check_hours(doc) -> dict:
    raw = {}
    if RAW.exists():
        raw = {f["properties"]["defibrillator_id"]: f["properties"] for f in json.loads(RAW.read_text(encoding="utf-8"))}
    cases = doc["cases"]
    unique("hours_cases.json", cases, "case_id")
    for c in cases:
        where = f"hours_cases.json:{c['case_id']}"
        check_schedule(f"{where}.expected", c["expected"])
        if c["origin"] == "synthetic" and not c["case_id"].startswith("syn-"):
            errors.append(f"{where}: synthetic cases must start with syn-")
        if c["origin"] == "warsaw_scb" and raw:
            source = raw.get(c["source_id"])
            if source is None:
                warnings.append(f"{where}: source_id {c['source_id']} is no longer in the city snapshot")
                continue
            for field, value in c["input"].items():
                if source.get(field) != value:
                    warnings.append(f"{where}: {field} changed in the city snapshot; re-check the expectation")
    return {c["case_id"]: c for c in cases}


def check_availability(doc, hours: dict) -> None:
    cases = doc["cases"]
    unique("availability_cases.json", cases, "case_id")
    for c in cases:
        where = f"availability_cases.json:{c['case_id']}"
        if c["schedule_ref"] not in hours:
            errors.append(f"{where}: schedule_ref {c['schedule_ref']!r} not found in hours_cases.json")
        times = [c["at"]] + ([c["until"]] if c["until"] else [])
        for t in times:
            try:
                if datetime.fromisoformat(t.replace("Z", "+00:00")).tzinfo is None:
                    raise ValueError
            except ValueError:
                errors.append(f"{where}: {t!r} must be RFC 3339 with an explicit offset")
        expected = c["expected"]
        if "error" not in expected:
            if expected.get("status") not in AVAILABILITY or not isinstance(expected.get("covers_interval"), bool):
                errors.append(f"{where}: expected needs status and covers_interval")
            elif expected["status"] != "open" and expected["covers_interval"]:
                errors.append(f"{where}: only an open AED can cover the interval")


def check_origins(doc) -> None:
    unique("origins.json", doc["origins"], "id")
    for o in doc["origins"]:
        lat, lon = o["origin"]["latitude"], o["origin"]["longitude"]
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            errors.append(f"origins.json:{o['id']}: coordinates out of WGS84 range")
        if o["expected"] not in {"inside", "outside"}:
            errors.append(f"origins.json:{o['id']}: expected must be inside or outside")


def main() -> int:
    hours_doc = load("hours_cases.json")
    hours = check_hours(hours_doc) if hours_doc else {}
    availability_doc = load("availability_cases.json")
    if availability_doc:
        check_availability(availability_doc, hours)
    origins_doc = load("origins.json")
    if origins_doc:
        check_origins(origins_doc)
    for doc, name in ((hours_doc, "hours_cases.json"), (availability_doc, "availability_cases.json"), (origins_doc, "origins.json")):
        if doc and doc.get("meta", {}).get("test_data") is not True:
            errors.append(f"{name}: meta.test_data must be true")

    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"error: {e}")
    counts = (len(hours), len(availability_doc["cases"]) if availability_doc else 0,
              len(origins_doc["origins"]) if origins_doc else 0)
    print(f"{'FAILED' if errors else 'OK'}: {counts[0]} hours, {counts[1]} availability, {counts[2]} origins")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

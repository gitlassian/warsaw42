"""Runs availability_cases.json against the real aed_availability() SQL function.

Needs Postgres + PostGIS with all migrations applied. Neither psql nor a Python driver is
required on the host: SQL is piped into psql inside a throwaway Docker container.

    docker run -d --name defiwawa-pg --platform linux/amd64 -e POSTGRES_PASSWORD=postgres postgis/postgis:16-3.5
    python3 fixtures/run_availability_sql.py --setup   # (re)creates database defiwawa_test: stubs, migrations, smoke test, seed
    python3 fixtures/run_availability_sql.py           # PASS/FAIL per case; exit code 1 if any case fails

--setup drops and recreates the database defiwawa_test only. It is created from template0 because the
postgis image pre-installs PostGIS into `public` of its default database, while the migrations expect it
in `extensions`. Every file in backend/supabase/migrations is applied unchanged, in filename order; the
stubs stand in for what Supabase provides. backend/supabase/tests/schema_smoke.sql then checks the stubs,
and backend/supabase/seed.sql loads the city data (710 AEDs, holidays, the Warsaw boundary).

Every fixture row is inserted in one transaction that ends with ROLLBACK, like
backend/supabase/tests/schema_smoke.sql. Only the standard library is used.

Environment: PG_CONTAINER (default defiwawa-pg), PG_DATABASE (default defiwawa_test),
PSQL to use another psql command instead of docker exec, e.g. PSQL="psql -h localhost -p 54329 -U postgres".
"""

import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"
SUPABASE = ROOT / "backend/supabase"
DATABASE = os.environ.get("PG_DATABASE", "defiwawa_test")

# What Supabase creates before migrations run: API roles, auth.users with auth.uid(), the extensions schema.
# auth.uid() reads the same setting as in Supabase, so schema_smoke.sql can switch users with set_config.
SUPABASE_STUBS = """
DO $$
DECLARE r text;
BEGIN
    FOREACH r IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
END $$;
ALTER ROLE service_role BYPASSRLS;
CREATE SCHEMA auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY, phone_confirmed_at timestamptz);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;
CREATE SCHEMA extensions;
GRANT USAGE ON SCHEMA public, extensions TO anon, authenticated, service_role;
"""

# Polish public holidays inside the fixture window (2026-10-19 .. 2026-12-24). seed.sql has the same
# dates; inserting them here as well keeps the run independent of the seed.
HOLIDAYS = [
    ("2026-11-01", "Wszystkich Świętych"),
    ("2026-11-11", "Narodowe Święto Niepodległości"),
    ("2026-12-24", "Wigilia Bożego Narodzenia"),
    ("2026-12-25", "Boże Narodzenie (pierwszy dzień)"),
    ("2026-12-26", "Boże Narodzenie (drugi dzień)"),
]

# hours_cases.json `kind` -> aeds.hours_status.
HOURS_STATUS = {"always_open": "24/7", "weekly": "scheduled", "unknown": "unknown"}
# review_status values that become aeds.hours_verified = true (the same rule as in the
# simplify_app_schema migration and pipeline/seed_sql.py).
VERIFIED = {"validated", "validated_partial"}

# Returns "status<TAB>covers<TAB>reasons", or "error<TAB>SQLSTATE<TAB>message", so one
# transaction survives the cases that are expected to fail.
RUNNER = r"""
CREATE FUNCTION pg_temp.run(p_id uuid, p_from timestamptz, p_until timestamptz) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM aed_availability(p_id, p_from, p_until);
    IF NOT FOUND THEN
        RETURN 'no_row' || E'\t\t';
    END IF;
    RETURN r.status || E'\t' || r.covers_interval || E'\t' || array_to_string(r.reasons, ',');
EXCEPTION WHEN OTHERS THEN
    RETURN 'error' || E'\t' || SQLSTATE || E'\t' || SQLERRM;
END
$$;
"""


def psql_command(database: str) -> list[str]:
    base = os.environ.get("PSQL")
    if base:
        command = shlex.split(base)
    else:
        command = ["docker", "exec", "-i", os.environ.get("PG_CONTAINER", "defiwawa-pg"), "psql", "-U", "postgres"]
    return command + ["-X", "-q", "-A", "-t", "-F", "\t", "-v", "ON_ERROR_STOP=1", "-d", database]


def psql(database: str, sql: str) -> str:
    done = subprocess.run(psql_command(database), input=sql, capture_output=True, text=True, encoding="utf-8")
    if done.returncode != 0:
        sys.exit(f"psql failed (exit {done.returncode}):\n{done.stderr.strip()}")
    return done.stdout


def lit(value) -> str:
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def minutes(hhmm: str) -> int:
    h, m = hhmm.split(":")
    return int(h) * 60 + int(m)


def setup() -> None:
    quiet = "SET client_min_messages = warning;\n"
    psql("postgres", f"DROP DATABASE IF EXISTS {DATABASE};\nCREATE DATABASE {DATABASE} TEMPLATE template0;\n")
    psql(DATABASE, quiet + SUPABASE_STUBS)
    migrations = sorted((SUPABASE / "migrations").glob("*.sql"))
    for migration in migrations:
        psql(DATABASE, quiet + migration.read_text(encoding="utf-8"))
    smoke = psql(DATABASE, quiet + (SUPABASE / "tests/schema_smoke.sql").read_text(encoding="utf-8"))
    if "schema_smoke: all checks passed" not in smoke:
        sys.exit(f"setup: schema_smoke.sql did not pass:\n{smoke.strip()}")
    psql(DATABASE, quiet + (SUPABASE / "seed.sql").read_text(encoding="utf-8"))
    counts = psql(DATABASE, "SELECT (SELECT count(*) FROM aeds) || ' AEDs, ' || (SELECT count(*) FROM public_holiday) "
                            "|| ' holidays, ' || (SELECT count(*) FROM service_area) || ' service area';").strip()
    print(f"setup: database {DATABASE} ready; {len(migrations)} migrations, schema_smoke passed, seed: {counts}")


def day_json(state: str, intervals: list) -> dict:
    return {"state": state, "intervals": [[minutes(start), minutes(end)] for start, end in intervals]}


def hours_json(expected: dict) -> dict:
    """hours_cases.json `expected` in the aeds.hours format from ENDPOINTS.md."""
    return {
        "weekly": {dow: day_json(day["state"], day["intervals"]) for dow, day in expected.get("weekly", {}).items()},
        "exceptions": {e["date"]: day_json(e["state"], e["intervals"]) for e in expected.get("date_exceptions", [])},
        "holiday_policy": expected["holiday_policy"],
    }


def schedule_sql(n: int, ref: str, hours: dict, text_changed: bool) -> str:
    """Inserts AED n with the parsed schedule `hours` (hours_cases.json `expected`)."""
    case = hours[ref]
    source = case["input"]
    expected = case["expected"]
    text = source.get("device_access_description")
    verified = expected["review_status"] in VERIFIED
    if text_changed:
        # The schema keeps no hash of the parsed text. By the import contract (backend/supabase/README.md)
        # changed text is stored unverified until it is re-parsed, so that is the state to test.
        text = (text or "") + " (tekst zmieniony przez miasto)"
        verified = False
    return (
        "INSERT INTO aeds (id, source_id, object_name, full_address, lon, lat, in_building, public_access,"
        " hours_text, hours_status, hours_verified, hours) VALUES ("
        f"{lit(f'00000000-0000-0000-0000-{n:012d}')}, {lit(f'fixture:{n}')}, {lit(ref)}, 'Testowa 1, 00-001 Warszawa', "
        f"{21 + n / 1000}, 52.2, {'true' if source.get('device_location') == 'Wewnątrz budynku' else 'false'}, "
        f"{lit('public' if source.get('device_public_access') == 'Publiczny' else 'unknown')}, {lit(text)}, "
        f"{lit(HOURS_STATUS[expected['kind']])}, {'true' if verified else 'false'}, "
        f"{lit(json.dumps(hours_json(expected)))});"
    )


def build_sql(cases: list, hours: dict) -> tuple[str, dict]:
    sql = [
        "SET client_encoding = 'UTF8';",
        "SET client_min_messages = warning;",
        "BEGIN;",
        "SET LOCAL search_path = public, extensions;",
        "SET LOCAL TimeZone = 'UTC';  -- results must not depend on the session time zone",
        "INSERT INTO public_holiday (on_date, name) VALUES "
        + ", ".join(f"({lit(d)}, {lit(name)})" for d, name in HOLIDAYS) + " ON CONFLICT (on_date) DO NOTHING;",
        RUNNER,
    ]
    aeds = {}
    for c in cases:
        key = (c["schedule_ref"], bool(c["state"].get("source_text_changed_after_parse")))
        if key not in aeds:
            aeds[key] = len(aeds) + 1
            sql.append(schedule_sql(aeds[key], key[0], hours, key[1]))
    for c in cases:
        key = (c["schedule_ref"], bool(c["state"].get("source_text_changed_after_parse")))
        aed_id = f"00000000-0000-0000-0000-{aeds[key]:012d}"
        sql.append(f"SELECT 'case', {lit(c['case_id'])}, pg_temp.run({lit(aed_id)}, {lit(c['at'])}, {lit(c['until'])});")
    sql.append("ROLLBACK;")
    return "\n".join(sql) + "\n", aeds


def check_origins() -> int:
    """origins.json against is_inside_warsaw() and the service_area boundary from seed.sql."""
    origins = json.loads((FIXTURES / "origins.json").read_text(encoding="utf-8"))["origins"]
    if psql(DATABASE, "SELECT count(*) FROM service_area;").strip() == "0":
        print("\norigins: skipped, service_area is empty (run --setup to load seed.sql)")
        return 0
    sql = "\n".join(
        f"SELECT {lit(o['id'])}, is_inside_warsaw({o['origin']['latitude']}, {o['origin']['longitude']});"
        for o in origins)
    inside = dict(line.split("\t") for line in psql(DATABASE, sql).splitlines())
    failed = 0
    print()
    for o in origins:
        got = "inside" if inside.get(o["id"]) == "t" else "outside"
        ok = got == o["expected"]
        failed += not ok
        print(f"{'PASS' if ok else 'FAIL'}  origin {o['id']:<20}  is_inside_warsaw: {got}"
              + ("" if ok else f" (expected {o['expected']})"))
    print(f"{len(origins)} origins: {len(origins) - failed} PASS, {failed} FAIL")
    return failed


def main() -> int:
    if "--setup" in sys.argv[1:]:
        setup()
        return 0

    hours = {c["case_id"]: c for c in json.loads((FIXTURES / "hours_cases.json").read_text(encoding="utf-8"))["cases"]}
    cases = json.loads((FIXTURES / "availability_cases.json").read_text(encoding="utf-8"))["cases"]
    sql, aeds = build_sql(cases, hours)

    results = {}
    for line in psql(DATABASE, sql).splitlines():
        parts = line.split("\t")
        if parts[0] == "case":
            results[parts[1]] = (parts[2:] + ["", "", ""])[:3]

    failed = reason_notes = 0
    width = max(len(c["case_id"]) for c in cases)
    for c in cases:
        expected = c["expected"]
        got = results.get(c["case_id"])
        if got is None:
            ok, detail = False, "no result row"
        elif "error" in expected:
            ok = got[0] == "error" and got[1] == "22023"
            detail = f"error {got[1]}: {got[2]}" if got[0] == "error" else f"expected SQLSTATE 22023, got {'/'.join(got)}"
        else:
            ok = got[0] == expected["status"] and got[1] == str(expected["covers_interval"]).lower()
            detail = f"{got[0]} covers={got[1]} reasons={got[2]}"
            if not ok:
                detail = f"expected {expected['status']} covers={str(expected['covers_interval']).lower()}, got " + detail
        failed += not ok
        print(f"{'PASS' if ok else 'FAIL'}  {c['case_id']:<{width}}  {detail}")
        hint = c.get("reason_hint")
        if got and got[0] != "error" and hint and hint not in got[2].split(","):
            reason_notes += 1
            print(f"{'':6}{'':<{width}}  note: reason_hint is {hint}, SQL returned {got[2]}")

    print(f"\n{len(cases)} cases on {len(aeds)} AEDs: {len(cases) - failed} PASS, {failed} FAIL; "
          f"reason differs from reason_hint in {reason_notes} (informational)")
    failed += check_origins()
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

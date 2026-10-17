"""Runs availability_cases.json against the real aed_availability() SQL function.

Needs Postgres + PostGIS with the initial migration applied. Neither psql nor a Python driver is
required on the host: SQL is piped into psql inside a throwaway Docker container.

    docker run -d --name defiwawa-pg --platform linux/amd64 -e POSTGRES_PASSWORD=postgres postgis/postgis:16-3.5
    python3 fixtures/run_availability_sql.py --setup   # (re)creates database defiwawa_test: Supabase stubs + migration
    python3 fixtures/run_availability_sql.py           # PASS/FAIL per case; exit code 1 if any case fails

--setup drops and recreates the database defiwawa_test only. It is created from template0 because the
postgis image pre-installs PostGIS into `public` of its default database, while the migration expects it
in `extensions`. The migration file is applied unchanged; the stubs stand in for what Supabase provides.

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
MIGRATION = ROOT / "backend/supabase/migrations/20261017120000_initial_schema.sql"
DATABASE = os.environ.get("PG_DATABASE", "defiwawa_test")

# What Supabase creates before migrations run: API roles, auth.users and the extensions schema.
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
CREATE TABLE auth.users (id uuid PRIMARY KEY);
CREATE SCHEMA extensions;
GRANT USAGE ON SCHEMA public, extensions TO anon, authenticated, service_role;
"""

# Polish public holidays inside the fixture window (2026-10-19 .. 2026-12-24).
HOLIDAYS = [
    ("2026-11-01", "Wszystkich Świętych"),
    ("2026-11-11", "Narodowe Święto Niepodległości"),
    ("2026-12-24", "Wigilia Bożego Narodzenia"),
    ("2026-12-25", "Boże Narodzenie (pierwszy dzień)"),
    ("2026-12-26", "Boże Narodzenie (drugi dzień)"),
]

HOURS_STATUS = {"always_open": "24/7", "weekly": "scheduled", "unknown": "unknown"}

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
    psql("postgres", f"DROP DATABASE IF EXISTS {DATABASE};\nCREATE DATABASE {DATABASE} TEMPLATE template0;\n")
    psql(DATABASE, "SET client_min_messages = warning;\n" + SUPABASE_STUBS)
    psql(DATABASE, "SET client_min_messages = warning;\n" + MIGRATION.read_text(encoding="utf-8"))
    extensions = psql(DATABASE, "SELECT extname || ' in ' || extnamespace::regnamespace FROM pg_extension "
                                "WHERE extname IN ('postgis', 'btree_gist') ORDER BY 1;")
    print(f"setup: database {DATABASE} ready; " + "; ".join(extensions.split("\n")).strip("; "))


def schedule_sql(n: int, ref: str, hours: dict, text_changed: bool) -> list[str]:
    """Inserts AED n with the parsed schedule `hours` (hours_cases.json `expected`)."""
    case = hours[ref]
    source = case["input"]
    expected = case["expected"]
    aed_id = f"00000000-0000-0000-0000-{n:012d}"
    text = source.get("device_access_description")
    sql = [
        "INSERT INTO aed (id, source_id, object_name, address_id, lon, lat, in_building, public_access,"
        " public_access_raw, availability_raw, access_text) VALUES ("
        f"{lit(aed_id)}, {lit(f'fixture:{n}')}, {lit(ref)}, 1, {21 + n / 1000}, 52.2, "
        f"{'true' if source.get('device_location') == 'Wewnątrz budynku' else 'false'}, "
        f"{lit('public' if source.get('device_public_access') == 'Publiczny' else 'unknown')}, "
        f"{lit(source.get('device_public_access'))}, {lit(source.get('device_availability'))}, {lit(text)});",
        "INSERT INTO aed_hours (id, aed_id, status, source_text, source_text_hash, holiday_policy,"
        " parse_source, parser_version, review_status) VALUES ("
        f"{n}, {lit(aed_id)}, {lit(HOURS_STATUS[expected['kind']])}, {lit(text)}, md5(coalesce({lit(text)}, '')), "
        f"{lit(expected['holiday_policy'])}, 'fixture', 'fixtures@1', {lit(expected['review_status'])});",
    ]
    for dow, day in sorted(expected.get("weekly", {}).items()):
        sql.append(f"INSERT INTO aed_day_state (hours_id, dow, state) VALUES ({n}, {dow}, {lit(day['state'])});")
        for start, end in day["intervals"]:
            sql.append(f"INSERT INTO aed_schedule (hours_id, dow, start_min, end_min) "
                       f"VALUES ({n}, {dow}, {minutes(start)}, {minutes(end)});")
    for exception in expected.get("date_exceptions", []):
        sql.append(f"INSERT INTO aed_hours_exception (hours_id, on_date, state) "
                   f"VALUES ({n}, {lit(exception['date'])}, {lit(exception['state'])});")
        for start, end in exception["intervals"]:
            sql.append(f"INSERT INTO aed_exception_interval (hours_id, on_date, start_min, end_min) "
                       f"VALUES ({n}, {lit(exception['date'])}, {minutes(start)}, {minutes(end)});")
    if text_changed:
        # The city changed the hours text after this schedule was parsed.
        sql.append(f"UPDATE aed SET access_text = coalesce(access_text, '') || ' (tekst zmieniony przez miasto)' "
                   f"WHERE id = {lit(aed_id)};")
    return sql


def build_sql(cases: list, hours: dict) -> tuple[str, dict]:
    sql = [
        "SET client_encoding = 'UTF8';",
        "SET client_min_messages = warning;",
        "BEGIN;",
        "SET LOCAL search_path = public, extensions;",
        "SET LOCAL TimeZone = 'UTC';  -- results must not depend on the session time zone",
        # Fixtures use small explicit ids; sequences survive ROLLBACK, so keep generated ids above them.
        "SELECT count(setval(s, greatest(nextval(s), 10000))) "
        "FROM unnest(ARRAY['aed_hours_id_seq', 'address_id_seq']) AS s;",
        "INSERT INTO address (id, street_raw, building_no, postcode) VALUES (1, 'Testowa', '1', '00-001');",
        "INSERT INTO public_holiday (on_date, name) VALUES "
        + ", ".join(f"({lit(d)}, {lit(name)})" for d, name in HOLIDAYS) + ";",
        RUNNER,
    ]
    aeds = {}
    for c in cases:
        key = (c["schedule_ref"], bool(c["state"].get("source_text_changed_after_parse")))
        if key not in aeds:
            aeds[key] = len(aeds) + 1
            sql += schedule_sql(aeds[key], key[0], hours, key[1])
    for c in cases:
        key = (c["schedule_ref"], bool(c["state"].get("source_text_changed_after_parse")))
        aed_id = f"00000000-0000-0000-0000-{aeds[key]:012d}"
        sql.append(f"SELECT 'case', {lit(c['case_id'])}, pg_temp.run({lit(aed_id)}, {lit(c['at'])}, {lit(c['until'])});")
    sql.append("ROLLBACK;")
    return "\n".join(sql) + "\n", aeds


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
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

-- Run after all migrations, with or without seed data. Rolls back test fixtures.
-- psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/schema_smoke.sql
BEGIN;
SET LOCAL search_path = public, extensions;
CREATE FUNCTION pg_temp.check_av(a uuid, at_time text, until_time text DEFAULT NULL)
RETURNS text LANGUAGE sql AS $$
    SELECT status || ':' || covers_interval FROM aed_availability(a, at_time::timestamptz, until_time::timestamptz)
$$;
CREATE FUNCTION pg_temp.denied(stmt text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE stmt;
    RAISE EXCEPTION 'Expected permission failure: %', stmt;
EXCEPTION WHEN insufficient_privilege THEN NULL;
END $$;
INSERT INTO aeds (id, source_id, object_name, full_address, lon, lat, public_access,
                  hours_status, hours_verified, hours)
VALUES ('00000000-0000-0000-0000-000000000101', 'test-schema-101', 'Test', 'Warszawa', 21.01, 52.21,
        'public', 'scheduled', true,
        '{"weekly":{"1":{"state":"open_intervals","intervals":[[480,960],[960,1080]]},
                    "2":{"state":"closed","intervals":[]}},
          "exceptions":{"2026-10-21":{"state":"open_intervals","intervals":[[0,1440]]},
                        "2026-10-22":{"state":"open_intervals","intervals":[[0,360]]}},
          "holiday_policy":"unknown"}');
INSERT INTO aeds (id, source_id, object_name, full_address, lon, lat, active)
VALUES ('00000000-0000-0000-0000-000000000102', 'test-schema-102', 'Inactive', 'Warszawa', 21.01, 52.21, false);
INSERT INTO public_holiday VALUES ('2026-11-11', 'Test holiday') ON CONFLICT DO NOTHING;
DO $$ DECLARE a uuid := '00000000-0000-0000-0000-000000000101'; BEGIN
    ASSERT pg_temp.check_av(a, '2026-10-19 15:59+02', '2026-10-19 16:01+02') = 'open:true', 'adjacent intervals merge';
    ASSERT pg_temp.check_av(a, '2026-10-19 17:59+02', '2026-10-19 18:01+02') = 'open:false', 'closing inside buffer';
    ASSERT pg_temp.check_av(a, '2026-10-19 18:00+02') = 'closed:false', 'closing boundary exclusive';
    ASSERT pg_temp.check_av(a, '2026-10-20 12:00+02') = 'closed:false', 'explicit closed day';
    ASSERT pg_temp.check_av(a, '2026-10-24 12:00+02') = 'unknown:false', 'missing day unknown';
    ASSERT pg_temp.check_av(a, '2026-10-21 23:59+02', '2026-10-22 00:01+02') = 'open:true', 'overnight exceptions';
    ASSERT pg_temp.check_av(a, '2026-11-11 12:00+01') = 'unknown:false', 'holiday unknown';
    UPDATE aeds SET hours_verified = false WHERE id = a;
    ASSERT pg_temp.check_av(a, '2026-10-19 12:00+02') = 'unknown:false', 'unreviewed hours unknown';
    UPDATE aeds SET hours_status = '24/7', hours_verified = true WHERE id = a;
    ASSERT pg_temp.check_av(a, '2026-10-24 12:00+02') = 'open:true', '24/7';
END $$;
SET LOCAL ROLE anon;
DO $$ BEGIN
    ASSERT EXISTS (SELECT 1 FROM aed_public WHERE source_id = 'test-schema-101');
    ASSERT NOT EXISTS (SELECT 1 FROM aeds WHERE source_id = 'test-schema-102');
    ASSERT EXISTS (SELECT 1 FROM aeds_nearby(52.21, 21.01) WHERE id = '00000000-0000-0000-0000-000000000101');
    ASSERT current_dataset_version() IS NOT NULL;
    ASSERT pg_temp.check_av('00000000-0000-0000-0000-000000000101', '2026-10-24 12:00+02') = 'open:true';
    PERFORM pg_temp.denied('SELECT * FROM reports');
    PERFORM pg_temp.denied('SELECT * FROM defi_legacy.report');
    PERFORM pg_temp.denied('UPDATE aeds SET active = false');
END $$;
RESET ROLE;
-- Anyone can report an active AED without a phone session; reports stay unreadable.
SET LOCAL ROLE anon;
INSERT INTO reports (aed_id, category, description) VALUES
    ('00000000-0000-0000-0000-000000000101', 'other', 'Anonymous report description');
DO $$ BEGIN
    PERFORM pg_temp.denied($q$INSERT INTO reports (aed_id, reporter_id, category, description) VALUES
        ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000202', 'other', 'Spoofed report description')$q$);
    PERFORM pg_temp.denied('SELECT * FROM reports');
    PERFORM pg_temp.denied('UPDATE reports SET status = ''accepted''');
END $$;
-- Inactive AEDs cannot be reported.
DO $$ BEGIN
    INSERT INTO reports (aed_id, category, description) VALUES
        ('00000000-0000-0000-0000-000000000102', 'other', 'Inactive AED report text');
    RAISE EXCEPTION 'Expected RLS failure for inactive AED';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END $$;
-- Five reports per client per hour, identified by the edge-set client IP.
SELECT set_config('request.headers', '{"cf-connecting-ip": "203.0.113.7"}', true);
INSERT INTO reports (aed_id, category, description, form_ms)
SELECT '00000000-0000-0000-0000-000000000101', 'other', 'Rate limit report ' || n, 5000 FROM generate_series(1, 5) n;
DO $$ BEGIN
    INSERT INTO reports (aed_id, category, description, form_ms) VALUES
        ('00000000-0000-0000-0000-000000000101', 'other', 'One report too many', 5000);
    RAISE EXCEPTION 'Expected client rate limit';
EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL;
END $$;
-- A client-supplied x-forwarded-for is not trusted as an identity.
SELECT set_config('request.headers', '{"x-forwarded-for": "198.51.100.1"}', true);
INSERT INTO reports (aed_id, category, description) VALUES
    ('00000000-0000-0000-0000-000000000101', 'other', 'Spoofed forwarded IP report');
-- Fast submissions and links are flagged, not rejected; clients cannot set flags themselves.
SELECT set_config('request.headers', '{"cf-connecting-ip": "203.0.113.8"}', true);
INSERT INTO reports (aed_id, category, description, form_ms) VALUES
    ('00000000-0000-0000-0000-000000000101', 'other', 'Cheap pills at https://spam.example', 500),
    ('00000000-0000-0000-0000-000000000101', 'other', 'Szafka jest zamknięta na klucz', 5000);
DO $$ BEGIN
    PERFORM pg_temp.denied($q$INSERT INTO reports (aed_id, category, description, flags) VALUES
        ('00000000-0000-0000-0000-000000000101', 'other', 'Self-cleared report text', '{}')$q$);
    PERFORM pg_temp.denied('SELECT * FROM report_queue');
    PERFORM pg_temp.denied($q$SELECT moderate_report_group('00000000-0000-0000-0000-000000000101', 'other', 'rejected', now())$q$);
END $$;
SELECT set_config('request.headers', '', true);
RESET ROLE;
DO $$ DECLARE q report_queue; BEGIN
    ASSERT (SELECT count(*) FROM reports WHERE client_hash = encode(sha256('203.0.113.7'::bytea), 'hex')) = 5;
    ASSERT NOT EXISTS (SELECT 1 FROM reports WHERE description = 'Anonymous report description' AND (client_hash IS NOT NULL OR flags <> '{}'));
    ASSERT (SELECT client_hash IS NULL AND flags = '{fast}' FROM reports WHERE description = 'Spoofed forwarded IP report');
    ASSERT (SELECT flags = '{fast,link}' FROM reports WHERE description LIKE 'Cheap pills%');
    ASSERT (SELECT flags = '{}' FROM reports WHERE description LIKE 'Szafka%');
    -- One queue row for the AED and category; only unflagged clients count, flagged text sorts last.
    SELECT * INTO STRICT q FROM report_queue WHERE aed_id = '00000000-0000-0000-0000-000000000101';
    ASSERT (q.reports, q.flagged, q.clients) = (9::bigint, 2::bigint, 2::bigint), format('queue counts %s', q);
    ASSERT 'Cheap pills at https://spam.example' <> ALL (q.sample_descriptions);
    ASSERT moderate_report_group(q.aed_id, q.category, 'rejected', q.last_at) = 9;
    ASSERT NOT EXISTS (SELECT 1 FROM report_queue WHERE aed_id = '00000000-0000-0000-0000-000000000101');
END $$;
ROLLBACK;
\echo 'schema_smoke: all checks passed'

-- Run after both migrations, with or without seed data. Rolls back test fixtures.
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
INSERT INTO auth.users (id, phone_confirmed_at) VALUES
    ('00000000-0000-0000-0000-000000000201', now()),
    ('00000000-0000-0000-0000-000000000202', NULL);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000201', true);
INSERT INTO reports (aed_id, reporter_id, category, description) VALUES
    ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000201', 'other', 'Test report description');
DO $$ BEGIN
    PERFORM pg_temp.denied($q$INSERT INTO reports (aed_id, reporter_id, category, description) VALUES
        ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000202', 'other', 'Spoofed report description')$q$);
    PERFORM pg_temp.denied('SELECT * FROM reports');
    PERFORM pg_temp.denied('UPDATE reports SET status = ''accepted''');
END $$;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000202', true);
DO $$ BEGIN
    PERFORM pg_temp.denied($q$INSERT INTO reports (aed_id, reporter_id, category, description) VALUES
        ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000202', 'other', 'Unverified report description')$q$);
END $$;
RESET ROLE;
ROLLBACK;
\echo 'schema_smoke: all checks passed'

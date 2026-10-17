-- Smoke tests for the initial schema. Runs in one transaction and rolls everything back.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/schema_smoke.sql
-- Any failed assertion aborts with a message.

BEGIN;
SET LOCAL search_path = public, extensions;

-- Readable fixed ids: u(1) = 00000000-0000-0000-0000-000000000001.
CREATE FUNCTION pg_temp.u(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
    SELECT ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
$$;

CREATE FUNCTION pg_temp.av(p_id uuid, p_from text, p_until text DEFAULT NULL) RETURNS text
LANGUAGE sql AS $$
    SELECT status || ':' || covers_interval || ':' || array_to_string(reasons, ',')
    FROM aed_availability(p_id, p_from::timestamptz, p_until::timestamptz)
$$;

-- Runs a statement and asserts it fails with the given message (or SQLSTATE).
CREATE FUNCTION pg_temp.fails(p_sql text, p_expected text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'expected "%" but succeeded: %', p_expected, p_sql;
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'expected "%' THEN RAISE; END IF;
    IF SQLERRM <> p_expected AND SQLSTATE <> p_expected THEN
        RAISE EXCEPTION 'expected "%" but got "%" (%): %', p_expected, SQLERRM, SQLSTATE, p_sql;
    END IF;
END
$$;

-- ---------------------------------------------------------------- fixtures
-- Monday 2026-10-19; Warsaw is UTC+2 (CEST) that week.

-- Fixtures use small explicit ids; sequences survive ROLLBACK, so keep generated ids above them.
SELECT count(setval(s, greatest(nextval(s), 10000)))
FROM unnest(ARRAY['aed_hours_id_seq', 'refresh_run_id_seq', 'dataset_version_id_seq']) AS s;

INSERT INTO service_area (boundary, source) VALUES (
    ST_Multi(ST_MakeEnvelope(20.85, 52.09, 21.28, 52.37, 4326)), 'test envelope'
);
INSERT INTO address (id, street_raw, building_no, postcode) VALUES (1, 'Rakowiecka', '25/27', '02-517');
INSERT INTO public_holiday VALUES ('2026-11-11', 'Narodowe Święto Niepodległości');
INSERT INTO auth.users (id) VALUES (pg_temp.u(1)), (pg_temp.u(2));   -- 1 = moderator, 2 = phone-verified reporter
INSERT INTO staff_member (user_id, role) VALUES (pg_temp.u(1), 'moderator');

INSERT INTO aed (id, source_id, object_name, address_id, lon, lat, in_building, public_access, access_text) VALUES
    (pg_temp.u(101), '101', 'Weekday hours', 1, 21.0148748892902, 52.2086170695684, true,  'public', 'Poniedziałek: godz. 8:00-18:00; Wtorek-Piątek: godz. 8:00-16:00'),
    (pg_temp.u(102), '102', 'Always open',   1, 21.0122, 52.2297, false, 'public', NULL),
    (pg_temp.u(103), '103', 'Overnight',     1, 21.0200, 52.2150, true,  'public', 'Pn 20:00-24:00, Wt 0:00-6:00'),
    (pg_temp.u(104), '104', 'Text changed',  1, 21.0100, 52.2100, true,  'public', 'nowy tekst'),
    (pg_temp.u(105), '105', 'Not reviewed',  1, 21.0150, 52.2090, true,  'public', 'cokolwiek'),
    (pg_temp.u(106), '106', 'Far away',      1, 21.0440, 52.2520, false, 'public', NULL);

INSERT INTO aed_hours (id, aed_id, status, source_text, source_text_hash, parse_source, parser_version, review_status)
SELECT s.hid, pg_temp.u(s.aid), s.status::hours_status, s.text, md5(coalesce(s.text, '')), 'test', 'test@1', s.review::review_status
FROM (VALUES
    (1, 101, 'scheduled', 'Poniedziałek: godz. 8:00-18:00; Wtorek-Piątek: godz. 8:00-16:00', 'validated_partial'),
    (2, 102, '24/7',      NULL,                                                              'validated'),
    (3, 103, 'scheduled', 'Pn 20:00-24:00, Wt 0:00-6:00',                                    'validated'),
    (4, 104, '24/7',      'stary tekst',                                                     'validated'),
    (5, 105, '24/7',      'cokolwiek',                                                       'pending'),
    (6, 106, '24/7',      NULL,                                                              'validated')
) AS s(hid, aid, status, text, review);

INSERT INTO aed_day_state (hours_id, dow, state) VALUES
    (1, 1, 'open_intervals'), (1, 2, 'open_intervals'), (1, 3, 'open_intervals'),
    (1, 4, 'open_intervals'), (1, 5, 'open_intervals'), (1, 6, 'unknown'), (1, 7, 'unknown'),
    (3, 1, 'open_intervals'), (3, 2, 'open_intervals');
INSERT INTO aed_schedule (hours_id, dow, start_min, end_min) VALUES
    (1, 1, 480, 1080), (1, 2, 480, 960), (1, 3, 480, 960), (1, 4, 480, 960), (1, 5, 480, 960),
    (3, 1, 1200, 1440), (3, 2, 0, 360);

INSERT INTO job (id, kind, dedupe_key, state, started_at, finished_at)
VALUES (pg_temp.u(900), 'import', 'warsaw:test', 'succeeded', now(), now());
INSERT INTO refresh_run (id, job_id, status, finished_at) VALUES (1, pg_temp.u(900), 'ok', now());
INSERT INTO dataset_version (id, cause, refresh_run_id) VALUES (1, 'import', 1);

-- ---------------------------------------------------------------- availability

DO $$ BEGIN
    ASSERT pg_temp.av(pg_temp.u(101), '2026-10-19 10:00+02', '2026-10-19 10:05+02') = 'open:true:weekly_hours',
        'open with the window inside hours';
    ASSERT pg_temp.av(pg_temp.u(101), '2026-10-19 17:57+02', '2026-10-19 18:01+02') = 'open:false:closes_within_window',
        'closes inside the access buffer';
    ASSERT pg_temp.av(pg_temp.u(101), '2026-10-19 17:55+02', '2026-10-19 18:00+02') = 'open:true:weekly_hours',
        'closing boundary is exclusive, so a window ending at 18:00 is covered';
    ASSERT pg_temp.av(pg_temp.u(101), '2026-10-19 18:00+02') = 'closed:false:outside_hours',
        'closed at the closing minute';
    ASSERT pg_temp.av(pg_temp.u(101), '2026-10-19 07:59:30+02') = 'closed:false:outside_hours',
        'seconds count: 07:59:30 is before opening';
    ASSERT pg_temp.av(pg_temp.u(101), '2026-10-24 12:00+02') = 'unknown:false:day_unknown',
        'unspecified Saturday stays unknown, not closed';
    ASSERT pg_temp.av(pg_temp.u(102), '2026-10-24 03:00+02', '2026-10-24 03:05+02') = 'open:true:always_open',
        '24/7';
    ASSERT pg_temp.av(pg_temp.u(102), '2026-11-11 03:00+01') = 'open:true:always_open',
        '24/7 ignores holiday policy';
    ASSERT pg_temp.av(pg_temp.u(103), '2026-10-19 23:58+02', '2026-10-20 00:03+02') = 'open:true:weekly_hours',
        'overnight window continues into the next day';
    ASSERT pg_temp.av(pg_temp.u(103), '2026-10-19 23:58+02', '2026-10-20 00:00+02') = 'open:true:weekly_hours',
        'window ending exactly at midnight';
    ASSERT pg_temp.av(pg_temp.u(104), '2026-10-19 10:00+02') = 'unknown:false:hours_outdated',
        'parse of an older text is not trusted';
    ASSERT pg_temp.av(pg_temp.u(105), '2026-10-19 10:00+02') = 'unknown:false:hours_not_validated',
        'unreviewed parse is not trusted';
    ASSERT pg_temp.av(pg_temp.u(101), '2026-11-11 10:00+01') = 'unknown:false:holiday_hours_unknown',
        'holiday with unknown policy';
    ASSERT aed_is_open(pg_temp.u(101), '2026-10-19 10:00+02') AND NOT aed_is_open(pg_temp.u(101), '2026-10-19 20:00+02')
        AND aed_is_open(pg_temp.u(101), '2026-10-24 12:00+02') IS NULL,
        'aed_is_open: true / false / null';
END $$;

INSERT INTO aed_hours_exception (hours_id, on_date, state) VALUES (1, '2026-10-20', 'closed');
DO $$ BEGIN
    ASSERT pg_temp.av(pg_temp.u(101), '2026-10-20 10:00+02') = 'closed:false:date_exception', 'date exception wins';
    PERFORM pg_temp.fails('INSERT INTO aed_schedule (hours_id, dow, start_min, end_min) VALUES (1, 6, 600, 700)', '23503');
    PERFORM pg_temp.fails('INSERT INTO aed_schedule (hours_id, dow, start_min, end_min) VALUES (1, 1, 1000, 1100)', '23P01');
    PERFORM pg_temp.fails($q$INSERT INTO aed_hours (aed_id, status, source_text_hash, parse_source, parser_version)
                            VALUES (pg_temp.u(101), 'unknown', 'x', 'test', 'test@1')$q$, '23505');
END $$;

-- ---------------------------------------------------------------- discovery

DO $$
DECLARE ids uuid[];
BEGIN
    ids := ARRAY(SELECT id FROM aeds_nearby(52.2080, 21.0130, 2000, 20));
    ASSERT ids[1] = pg_temp.u(101), 'nearest first';
    ASSERT NOT (pg_temp.u(106) = ANY (ids)), 'radius respected';
    ASSERT is_inside_warsaw(52.2080, 21.0130) AND NOT is_inside_warsaw(50.06, 19.94), 'service area';
END $$;

-- ---------------------------------------------------------------- overrides (§8)

DO $$
DECLARE
    v_before bigint := current_dataset_version();
    v_id bigint;
BEGIN
    -- Moving an AED away removes it from nearby results and shows the corrected position.
    INSERT INTO aed_override (aed_id, type, value, reason, created_by)
    VALUES (pg_temp.u(101), 'coordinates', '{"lon": 21.2, "lat": 52.3}', 'wrong pin', pg_temp.u(1))
    RETURNING id INTO v_id;
    ASSERT current_dataset_version() > v_before, 'override publishes a new dataset version';
    ASSERT NOT EXISTS (SELECT 1 FROM aeds_nearby(52.2080, 21.0130) WHERE id = pg_temp.u(101)), 'effective location used';
    ASSERT (SELECT lon FROM aed_public WHERE id = pg_temp.u(101)) = 21.2, 'public view shows corrected coordinates';

    PERFORM pg_temp.fails(format($q$INSERT INTO aed_override (aed_id, type, value, reason, created_by)
        VALUES (%L, 'coordinates', '{"lon": 21.1, "lat": 52.3}', 'second', %L)$q$, pg_temp.u(101), pg_temp.u(1)),
        '23P01');  -- overlapping active override -> 409 override_conflict
    PERFORM pg_temp.fails(format($q$INSERT INTO aed_override (aed_id, type, value, reason, created_by)
        VALUES (%L, 'operational_status', '{"operational_status": "broken"}', 'x', %L)$q$, pg_temp.u(102), pg_temp.u(1)),
        '23514');
    PERFORM pg_temp.fails(format($q$INSERT INTO aed_override (aed_id, type, value, reason, created_by)
        VALUES (%L, 'operational_status', '{"operational_status": "confirmed_unavailable"}', 'x', %L)$q$, pg_temp.u(102), pg_temp.u(2)),
        'not_moderator');
    PERFORM pg_temp.fails(format('UPDATE aed_override SET reason = %L WHERE id = %s', 'edited', v_id), 'override_immutable');
    PERFORM pg_temp.fails(format('SELECT revoke_override(%s, %L, 7, %L)', v_id, 'fixed', pg_temp.u(1)), 'version_conflict');

    ASSERT revoke_override(v_id, 'pin fixed at source', 1, pg_temp.u(1)) = 2, 'revoked with expected_version';
    ASSERT EXISTS (SELECT 1 FROM aeds_nearby(52.2080, 21.0130) WHERE id = pg_temp.u(101)), 'revoked override no longer applies';
    PERFORM pg_temp.fails(format('DELETE FROM aed_override WHERE id = %s', v_id), '23503');  -- audit history is kept
END $$;

DO $$ BEGIN
    INSERT INTO aed_override (aed_id, type, value, reason, created_by)
    VALUES (pg_temp.u(102), 'operational_status', '{"operational_status": "confirmed_unavailable"}', 'no pads', pg_temp.u(1));
    ASSERT (SELECT operational_status FROM aed_public WHERE id = pg_temp.u(102)) = 'confirmed_unavailable', 'operational override';

    INSERT INTO aed_override (aed_id, type, value, reason, created_by)
    VALUES (pg_temp.u(103), 'access', '{"public_access": "restricted", "access_instructions": "Ochrona, parter"}', 'checked', pg_temp.u(1));
    ASSERT (SELECT public_access::text || '/' || access_instructions FROM aed_public WHERE id = pg_temp.u(103))
        = 'restricted/Ochrona, parter', 'access override';

    -- An hours override replaces the parsed schedule, including its unknown weekend.
    INSERT INTO aed_hours (id, aed_id, origin, status, parse_source, parser_version, review_status)
    VALUES (50, pg_temp.u(101), 'override', '24/7', 'manual', 'manual', 'validated');
    INSERT INTO aed_override (aed_id, type, value, hours_id, reason, created_by)
    VALUES (pg_temp.u(101), 'hours', '{"timezone": "Europe/Warsaw", "kind": "always_open"}', 50, 'phoned the venue', pg_temp.u(1));
    ASSERT pg_temp.av(pg_temp.u(101), '2026-10-24 12:00+02') = 'open:true:always_open', 'hours override applied';
    ASSERT (SELECT hours_overridden FROM aed_public WHERE id = pg_temp.u(101)), 'override visible in public view';
END $$;

-- ---------------------------------------------------------------- reports (§4) and moderation (§8)

INSERT INTO otp_challenge (id, user_id, aed_id, category, description, expires_at, verified_at) VALUES
    (pg_temp.u(201), pg_temp.u(2), pg_temp.u(101), 'malfunction', '  Brak elektrod w szafce  ', now() + interval '5 minutes', now()),
    (pg_temp.u(202), pg_temp.u(2), pg_temp.u(101), 'other',       'Szafka jest zamknięta',      now() + interval '5 minutes', now());
INSERT INTO report_authorization (challenge_id, token_hash, expires_at, created_at) VALUES
    (pg_temp.u(201), repeat('a', 64), now() + interval '10 minutes', now()),
    (pg_temp.u(202), repeat('b', 64), now() - interval '1 minute',   now() - interval '5 minutes');

DO $$
DECLARE
    r record;
    v_replay record;
    v_version integer;
BEGIN
    PERFORM pg_temp.fails($q$INSERT INTO otp_challenge (user_id, aed_id, category, description, expires_at)
        VALUES (pg_temp.u(2), pg_temp.u(101), 'other', '   za krótki ', now() + interval '1 minute')$q$, '23514');
    PERFORM pg_temp.fails($q$INSERT INTO otp_challenge (user_id, aed_id, category, description, expires_at)
        VALUES (pg_temp.u(2), pg_temp.u(101), 'other', 'Opis wystarczająco długi', now() + interval '6 minutes')$q$, '23514');

    SELECT * INTO r FROM submit_report(repeat('a', 64), pg_temp.u(301));
    ASSERT NOT r.replayed AND r.status = 'pending', 'report created as pending';
    ASSERT (SELECT description FROM report WHERE id = r.report_id) = 'Brak elektrod w szafce', 'bound draft, trimmed';

    SELECT * INTO v_replay FROM submit_report(repeat('a', 64), pg_temp.u(301));
    ASSERT v_replay.replayed AND v_replay.report_id = r.report_id, 'same Idempotency-Key returns the original receipt';
    ASSERT (SELECT count(*) FROM report) = 1, 'no duplicate report';

    PERFORM pg_temp.fails(format('SELECT submit_report(%L, %L)', repeat('a', 64), pg_temp.u(302)), 'authorization_used');
    PERFORM pg_temp.fails(format('SELECT submit_report(%L, %L)', repeat('b', 64), pg_temp.u(303)), 'report_authorization_expired');
    PERFORM pg_temp.fails(format('SELECT submit_report(%L, %L)', repeat('c', 64), pg_temp.u(304)), 'report_authorization_invalid');

    PERFORM pg_temp.fails(format('SELECT moderate_report(%L, %L, %L, 1, %L)', r.report_id, 'accepted', 'ok', pg_temp.u(2)), 'not_moderator');
    PERFORM pg_temp.fails(format('SELECT moderate_report(%L, %L, %L, 1, %L)', r.report_id, 'resolved', 'ok', pg_temp.u(1)), 'invalid_transition');
    v_version := moderate_report(r.report_id, 'accepted', 'confirmed on site', 1, pg_temp.u(1));
    ASSERT v_version = 2, 'moderation bumps version';
    PERFORM pg_temp.fails(format('SELECT moderate_report(%L, %L, %L, 1, %L)', r.report_id, 'resolved', 'ok', pg_temp.u(1)), 'version_conflict');
    ASSERT moderate_report(r.report_id, 'resolved', 'pads replaced', 2, pg_temp.u(1)) = 3, 'accepted -> resolved';
    ASSERT (SELECT count(*) FROM report_moderation_event WHERE report_id = r.report_id) = 2, 'moderation history';
END $$;

-- ---------------------------------------------------------------- jobs (§9–10) and offline (§6)

DO $$ BEGIN
    INSERT INTO job (kind, dedupe_key) VALUES ('parse_hours', 'aed:101:hash:v1');
    PERFORM pg_temp.fails($q$INSERT INTO job (kind, dedupe_key) VALUES ('parse_hours', 'aed:101:hash:v1')$q$, '23505');
END $$;

INSERT INTO offline_region (id, name, bounds) VALUES ('warszawa', 'Warszawa', ST_MakeEnvelope(20.85, 52.09, 21.28, 52.37, 4326));
INSERT INTO offline_asset (id, region_id, kind, version, format, storage_path, size_bytes, sha256, dataset_version_id) VALUES
    (pg_temp.u(401), 'warszawa', 'basemap',  '2026.10', 'pmtiles', 'offline/warszawa/basemap-2026.10.pmtiles', 1000, repeat('1', 64), NULL),
    (pg_temp.u(402), 'warszawa', 'aed_data', '1',       'json.gz', 'offline/warszawa/aed-1.json.gz',         100,  repeat('2', 64), 1),
    (pg_temp.u(403), 'warszawa', 'aed_data', '2',       'json.gz', 'offline/warszawa/aed-2.json.gz',         100,  repeat('3', 64), 1);
INSERT INTO offline_release (region_id, version, schema_version, basemap_asset_id, aed_asset_id, dataset_version_id, attribution, published_at) VALUES
    ('warszawa', 1, 1, pg_temp.u(401), pg_temp.u(402), 1, 'Dane: m.st. Warszawa; mapa: © OpenStreetMap', now()),
    ('warszawa', 2, 1, pg_temp.u(401), pg_temp.u(403), 1, 'Dane: m.st. Warszawa; mapa: © OpenStreetMap', NULL);

-- ---------------------------------------------------------------- access control

INSERT INTO aed_photo (aed_id, file_name, public_file_name) VALUES (pg_temp.u(101), 'IMG_0001.jpg', 'aed-1.jpg');

SET LOCAL ROLE anon;
DO $$ BEGIN
    ASSERT (SELECT count(*) FROM aed_public) = 6, 'anon reads the public view';
    ASSERT (SELECT open_now FROM aed_public WHERE id = pg_temp.u(106)), 'availability works for anon';
    ASSERT current_dataset_version() IS NOT NULL, 'dataset version readable';
    ASSERT EXISTS (SELECT 1 FROM aeds_nearby(52.2080, 21.0130)), 'nearby works for anon';
    ASSERT (SELECT public_file_name FROM aed_photo LIMIT 1) = 'aed-1.jpg', 'public photo readable';
    ASSERT (SELECT array_agg(version) FROM offline_release) = '{1}', 'only published releases';
    ASSERT (SELECT count(*) FROM offline_asset) = 2, 'only assets of published releases';
END $$;

DO $$
DECLARE stmt text;
BEGIN
    FOREACH stmt IN ARRAY ARRAY[
        'SELECT * FROM report',
        'SELECT * FROM report_authorization',
        'SELECT * FROM otp_challenge',
        'SELECT * FROM report_moderation_event',
        'SELECT * FROM aed_override',
        'SELECT * FROM staff_member',
        'SELECT * FROM audit_flag',
        'SELECT * FROM source_snapshot',
        'SELECT * FROM job',
        'SELECT file_name FROM aed_photo',
        'UPDATE aed SET object_name = ''x''',
        'INSERT INTO staff_member (user_id, role) VALUES (pg_temp.u(2), ''admin'')',
        'SELECT submit_report(repeat(''a'', 64), pg_temp.u(999))',
        'SELECT moderate_report(pg_temp.u(1), ''accepted'', ''x'', 1, pg_temp.u(1))',
        'SELECT is_staff(pg_temp.u(1))'
    ] LOOP
        PERFORM pg_temp.fails(stmt, '42501');
    END LOOP;
END $$;
RESET ROLE;

ROLLBACK;
\echo 'schema_smoke: all checks passed'

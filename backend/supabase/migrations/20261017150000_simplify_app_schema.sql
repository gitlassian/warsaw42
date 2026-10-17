-- One AED row contains its address, access details and JSON opening hours.
-- Keep the original schema as a private archive; never drop existing data.
BEGIN;
SET LOCAL search_path = public, extensions;

-- Timed corrections need an explicit decision before switching to direct edits.
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM aed_override WHERE revoked_at IS NULL
               AND (valid_from > now() OR valid_until > now())) THEN
        RAISE EXCEPTION 'Resolve scheduled/temporary AED overrides before simplifying the schema';
    END IF;
END $$;

CREATE TEMP TABLE migrate_aeds ON COMMIT DROP AS
SELECT a.id, a.source_id, a.object_name, ad.full_address, e.lon, e.lat,
       a.in_building, a.floor, e.access_instructions, e.public_access::text AS public_access,
       e.operational_status::text AS operational_status, a.access_text AS hours_text,
       coalesce(h.status::text, 'unknown') AS hours_status,
       coalesce(e.hours_overridden OR (h.review_status IN ('validated', 'validated_partial')
           AND h.source_text_hash = a.access_text_hash), false) AS hours_verified,
       jsonb_build_object(
           'weekly', coalesce((SELECT jsonb_object_agg(d.dow::text, jsonb_build_object(
               'state', d.state, 'intervals', coalesce((SELECT jsonb_agg(jsonb_build_array(s.start_min, s.end_min) ORDER BY s.start_min)
                   FROM aed_schedule s WHERE s.hours_id = h.id AND s.dow = d.dow), '[]'::jsonb)))
               FROM aed_day_state d WHERE d.hours_id = h.id), '{}'::jsonb),
           'exceptions', coalesce((SELECT jsonb_object_agg(x.on_date::text, jsonb_build_object(
               'state', x.state, 'intervals', coalesce((SELECT jsonb_agg(jsonb_build_array(i.start_min, i.end_min) ORDER BY i.start_min)
                   FROM aed_exception_interval i WHERE i.hours_id = h.id AND i.on_date = x.on_date), '[]'::jsonb)))
               FROM aed_hours_exception x WHERE x.hours_id = h.id), '{}'::jsonb),
           'holiday_policy', coalesce(h.holiday_policy::text, 'unknown')) AS hours,
       a.removed_at IS NULL AS active,
       EXISTS (SELECT 1 FROM aed_override o WHERE o.aed_id = a.id AND o.revoked_at IS NULL
               AND o.valid_from <= now() AND o.valid_until IS NULL) AS manually_edited,
       a.last_fetched_at AS updated_at
FROM aed a JOIN address ad ON ad.id = a.address_id
CROSS JOIN LATERAL aed_effective_state(a.id) e
LEFT JOIN aed_hours h ON h.id = e.hours_id;

CREATE SCHEMA defi_legacy;
REVOKE ALL ON SCHEMA defi_legacy FROM PUBLIC, anon, authenticated;
-- Only objects belonging to this app; extensions stay where they are.
DO $$ DECLARE r record; BEGIN
    FOR r IN SELECT c.relname, c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v')
          AND c.relname IN ('data_source', 'service_area', 'district', 'public_holiday', 'building', 'address', 'job', 'refresh_run', 'source_snapshot', 'dataset_version', 'aed', 'aed_hours', 'aed_day_state', 'aed_schedule', 'aed_hours_exception', 'aed_exception_interval', 'hours_cache', 'aed_photo', 'staff_member', 'otp_challenge', 'report_authorization', 'report', 'report_moderation_event', 'aed_override', 'osm_aed', 'audit_flag', 'aed_change', 'population_cell', 'coverage_layer', 'coverage_region', 'coverage_hour', 'relocation_rank', 'bo_project', 'offline_region', 'offline_asset', 'offline_release', 'aed_public')
          AND c.relname NOT IN ('service_area', 'public_holiday')
          AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_class'::regclass
                          AND d.objid = c.oid AND d.deptype = 'e')
    LOOP
        EXECUTE format('ALTER %s public.%I SET SCHEMA defi_legacy',
            CASE r.relkind WHEN 'v' THEN 'VIEW' ELSE 'TABLE' END, r.relname);
    END LOOP;
    FOR r IN SELECT p.oid::regprocedure AS signature FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
        AND p.proname IN ('fmt_street', 'dist_m', 'floor_label', 'current_dataset_version', 'is_inside_warsaw', 'is_staff', 'aed_effective_state', 'aed_day', 'aed_availability', 'aed_is_open', 'aeds_nearby', 'submit_report', 'moderate_report', 'revoke_override', 'aed_override_guard', 'aed_override_publish')
        AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass
                        AND d.objid = p.oid AND d.deptype = 'e')
    LOOP
        EXECUTE format('ALTER FUNCTION %s SET SCHEMA defi_legacy', r.signature);
    END LOOP;
    FOR r IN SELECT t.typname FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'public' AND t.typtype = 'e' AND t.typname IN ('hours_status', 'day_state', 'holiday_policy', 'review_status', 'availability_state', 'public_access', 'operational_status', 'floor_source', 'match_status', 'flag_severity', 'change_type', 'job_state', 'report_category', 'report_status', 'asset_kind')
    LOOP
        EXECUTE format('ALTER TYPE public.%I SET SCHEMA defi_legacy', r.typname);
    END LOOP;
END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA defi_legacy FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA defi_legacy FROM anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA defi_legacy FROM PUBLIC, anon, authenticated;

CREATE TABLE aeds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id text NOT NULL UNIQUE,
    object_name text NOT NULL,
    full_address text NOT NULL,
    lon double precision NOT NULL CHECK (lon BETWEEN 20.7 AND 21.4),
    lat double precision NOT NULL CHECK (lat BETWEEN 52.0 AND 52.5),
    location geography(Point, 4326) GENERATED ALWAYS AS
        (ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography) STORED,
    in_building boolean NOT NULL DEFAULT false,
    floor smallint,
    access_instructions text,
    public_access text NOT NULL DEFAULT 'unknown' CHECK (public_access IN ('public', 'restricted', 'unknown')),
    operational_status text NOT NULL DEFAULT 'unknown'
        CHECK (operational_status IN ('unknown', 'confirmed_unavailable', 'confirmed_operational')),
    hours_text text,
    hours_status text NOT NULL DEFAULT 'unknown' CHECK (hours_status IN ('24/7', 'scheduled', 'unknown')),
    hours_verified boolean NOT NULL DEFAULT false,
    hours jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(hours) = 'object'),
    active boolean NOT NULL DEFAULT true,
    manually_edited boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX aeds_location_idx ON aeds USING gist (location) WHERE active;
INSERT INTO aeds (id, source_id, object_name, full_address, lon, lat, in_building, floor,
    access_instructions, public_access, operational_status, hours_text, hours_status,
    hours_verified, hours, active, manually_edited, updated_at)
SELECT * FROM migrate_aeds;

CREATE TABLE reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    aed_id uuid NOT NULL REFERENCES aeds,
    reporter_id uuid REFERENCES auth.users ON DELETE SET NULL,
    category text NOT NULL CHECK (category IN ('missing', 'malfunction', 'inaccessible', 'incorrect_hours', 'incorrect_location', 'other')),
    description text NOT NULL CHECK (length(btrim(description)) BETWEEN 10 AND 2000),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'resolved')),
    created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO reports (id, aed_id, reporter_id, category, description, status, created_at)
SELECT id, aed_id, reporter_id, category::text, description, status::text, created_at FROM defi_legacy.report;
CREATE INDEX reports_pending_idx ON reports (created_at) WHERE status = 'pending';

-- Small public documents: dataset status, coverage GeoJSON, offline manifest.
CREATE TABLE app_data (
    key text PRIMARY KEY,
    data jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION touch_updated_at() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
CREATE TRIGGER aeds_updated BEFORE UPDATE ON aeds FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER app_data_updated BEFORE UPDATE ON app_data FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

ALTER TABLE aeds ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_data ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON aeds, reports, app_data FROM anon, authenticated;
GRANT SELECT ON aeds, app_data TO anon, authenticated;
CREATE POLICY public_read ON aeds FOR SELECT TO anon, authenticated USING (active);
CREATE POLICY public_read ON app_data FOR SELECT TO anon, authenticated USING (true);
-- Reporting uses the existing Supabase phone session. No custom token/challenge tables.
CREATE FUNCTION phone_verified() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT EXISTS (SELECT 1 FROM auth.users WHERE id = auth.uid() AND phone_confirmed_at IS NOT NULL)
$$;
REVOKE ALL ON FUNCTION phone_verified() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION phone_verified() TO authenticated;
GRANT INSERT (id, aed_id, reporter_id, category, description) ON reports TO authenticated;
CREATE POLICY submit_own_report ON reports FOR INSERT TO authenticated
    WITH CHECK (reporter_id = auth.uid() AND public.phone_verified()
        AND EXISTS (SELECT 1 FROM public.aeds WHERE id = aed_id AND active));
GRANT ALL ON aeds, reports, app_data TO service_role;

-- Compatibility for the three existing routing Edge Functions.
CREATE VIEW aed_public WITH (security_invoker = true) AS
SELECT id, source_id, lon, lat, object_name, full_address, access_instructions,
       public_access, operational_status FROM aeds WHERE active;
GRANT SELECT ON aed_public TO anon, authenticated;

CREATE FUNCTION current_dataset_version() RETURNS bigint LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT (extract(epoch FROM max(updated_at)) * 1000000)::bigint FROM aeds
$$;
CREATE FUNCTION is_inside_warsaw(p_lat double precision, p_lon double precision) RETURNS boolean
LANGUAGE sql STABLE SET search_path = public, extensions AS $$
    SELECT EXISTS (SELECT 1 FROM service_area
        WHERE ST_Covers(boundary, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)))
$$;
CREATE FUNCTION aeds_nearby(p_lat double precision, p_lon double precision,
    p_radius_m integer DEFAULT 2000, p_limit integer DEFAULT 20, p_exclude uuid[] DEFAULT '{}')
RETURNS TABLE (id uuid, distance_m double precision)
LANGUAGE sql STABLE SET search_path = public, extensions AS $$
    SELECT a.id, ST_Distance(a.location, o.g) AS distance_m
    FROM aeds a CROSS JOIN (SELECT ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography g) o
    WHERE a.active AND NOT (a.id = ANY(p_exclude))
        AND ST_DWithin(a.location, o.g, greatest(0, least(p_radius_m, 20000)))
    ORDER BY distance_m, a.id LIMIT greatest(0, least(p_limit, 100))
$$;

CREATE FUNCTION aed_day(p_aed_id uuid, p_day date)
RETURNS TABLE (state text, reason text, open nummultirange)
LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE h aeds; d jsonb; policy text;
BEGIN
    SELECT * INTO h FROM aeds WHERE id = p_aed_id AND active;
    d := h.hours->'exceptions'->p_day::text;
    IF d IS NULL THEN
        IF h.hours_status = '24/7' THEN
            RETURN QUERY SELECT 'open_intervals', 'always_open', nummultirange(numrange(0,1440,'[)')); RETURN;
        END IF;
        policy := coalesce(h.hours->>'holiday_policy', 'unknown');
        IF EXISTS (SELECT 1 FROM public_holiday WHERE on_date = p_day) AND policy <> 'regular_hours' THEN
            RETURN QUERY SELECT CASE WHEN policy = 'closed' THEN 'closed' ELSE 'unknown' END,
                'holiday_hours', '{}'::nummultirange; RETURN;
        END IF;
        d := h.hours->'weekly'->(extract(isodow FROM p_day)::integer)::text;
    END IF;
    RETURN QUERY SELECT coalesce(d->>'state', 'unknown'), 'listed_hours',
        coalesce((SELECT range_agg(numrange((i->>0)::numeric, (i->>1)::numeric, '[)'))
            FROM jsonb_array_elements(coalesce(d->'intervals', '[]')) i), '{}'::nummultirange);
END $$;
CREATE FUNCTION aed_availability(p_aed_id uuid, p_from timestamptz DEFAULT now(), p_until timestamptz DEFAULT NULL)
RETURNS TABLE (status text, covers_interval boolean, reasons text[])
LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE
    v_until    timestamptz := coalesce(p_until, p_from);
    v_from_l   timestamp := p_from AT TIME ZONE 'Europe/Warsaw';
    v_until_l  timestamp := coalesce(p_until, p_from) AT TIME ZONE 'Europe/Warsaw';
    h          aeds;
    v_day      date := (p_from AT TIME ZONE 'Europe/Warsaw')::date;
    v_cursor   numeric;
    v_end      numeric;
    v_first    boolean := true;
    d          record;
BEGIN
    IF v_until < p_from THEN
        RAISE EXCEPTION 'p_until must not precede p_from' USING ERRCODE = '22023';
    END IF;
    IF v_until - p_from > interval '2 days' THEN
        RAISE EXCEPTION 'availability window is limited to 2 days' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO h FROM aeds WHERE id = p_aed_id AND active;
    IF NOT FOUND OR NOT h.hours_verified OR h.hours_status = 'unknown' THEN
        RETURN QUERY SELECT 'unknown'::text, false, ARRAY['hours_unknown']; RETURN;
    END IF;

    v_cursor := extract(epoch FROM v_from_l::time) / 60;
    LOOP
        SELECT * INTO d FROM aed_day(p_aed_id, v_day);

        IF d.state <> 'open_intervals' THEN
            IF v_first THEN
                RETURN QUERY SELECT
                    CASE d.state WHEN 'closed' THEN 'closed'::text ELSE 'unknown'::text END,
                    false, ARRAY[d.reason];
            ELSE
                RETURN QUERY SELECT 'open'::text, false, ARRAY['next_day_' || d.reason];
            END IF;
            RETURN;
        END IF;

        SELECT upper(r) INTO v_end FROM unnest(d.open) r WHERE r @> v_cursor;
        IF v_end IS NULL THEN
            IF v_first THEN
                RETURN QUERY SELECT 'closed'::text, false, ARRAY['outside_hours'];
            ELSE
                RETURN QUERY SELECT 'open'::text, false, ARRAY['closes_within_window'];
            END IF;
            RETURN;
        END IF;

        -- Window ends today, or exactly at midnight after an interval that runs to 24:00.
        IF (v_until_l::date = v_day AND extract(epoch FROM v_until_l::time) / 60 <= v_end)
           OR (v_until_l = (v_day + 1)::timestamp AND v_end = 1440) THEN
            RETURN QUERY SELECT 'open'::text, true, ARRAY[d.reason]; RETURN;
        END IF;
        IF v_end < 1440 THEN
            RETURN QUERY SELECT 'open'::text, false, ARRAY['closes_within_window']; RETURN;
        END IF;

        v_day := v_day + 1;
        v_cursor := 0;
        v_first := false;
    END LOOP;
END
$$;

REVOKE ALL ON FUNCTION touch_updated_at(), current_dataset_version(),
    is_inside_warsaw(double precision, double precision),
    aeds_nearby(double precision, double precision, integer, integer, uuid[]),
    aed_day(uuid, date), aed_availability(uuid, timestamptz, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION current_dataset_version(), is_inside_warsaw(double precision, double precision),
    aeds_nearby(double precision, double precision, integer, integer, uuid[]),
    aed_day(uuid, date), aed_availability(uuid, timestamptz, timestamptz) TO anon, authenticated, service_role;
COMMIT;

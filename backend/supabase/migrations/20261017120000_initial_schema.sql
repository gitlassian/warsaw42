-- DefiWawa: initial database schema (Supabase Postgres + PostGIS). Contract: ENDPOINTS.md.
--
-- Conventions
--   ids       aed.id is our stable uuid (the API's string id); aed.source_id is defibrillator_id from Warsaw.
--   location  WGS84; lon/lat are stored as given and `location` is derived from them.
--   floor     0 = ground floor (parter), 1 = first floor above ground ("I piętro"), -1 = basement, NULL = unknown
--   dow       ISO weekday, 1 = Monday ... 7 = Sunday (same as the API schedule contract)
--   minutes   minutes since local midnight in Europe/Warsaw (0..1440, 1440 = 24:00).
--             Opening boundary inclusive, closing boundary exclusive.
--             Intervals that cross midnight are stored as two rows (end of day D, start of day D+1).
--   version   dataset_version grows on every published import and every override change.
--
-- Access model
--   Every table has RLS enabled. anon/authenticated get read-only access to public data only.
--   Phone-verified reporters are ordinary auth users and get nothing extra; moderators are listed
--   in staff_member and act through the Edge Functions (service_role) and the functions below.
--   Views are security_invoker. Private data reaches public reads only through SECURITY DEFINER
--   helpers that return derived values (aed_effective_state, aeds_nearby, current_dataset_version).

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;
SET search_path = public, extensions;

CREATE TYPE hours_status       AS ENUM ('24/7', 'scheduled', 'unknown');
CREATE TYPE day_state          AS ENUM ('open_intervals', 'closed', 'unknown');
CREATE TYPE holiday_policy     AS ENUM ('unknown', 'closed', 'regular_hours');
CREATE TYPE review_status      AS ENUM ('pending', 'validated', 'validated_partial', 'needs_review', 'rejected');
CREATE TYPE availability_state AS ENUM ('open', 'closed', 'unknown');
CREATE TYPE public_access      AS ENUM ('public', 'restricted', 'unknown');
CREATE TYPE operational_status AS ENUM ('unknown', 'confirmed_unavailable', 'confirmed_operational');
CREATE TYPE floor_source       AS ENUM ('text', 'osm', 'manual');
CREATE TYPE match_status       AS ENUM ('matched', 'far', 'no_match');
CREATE TYPE flag_severity      AS ENUM ('info', 'warning', 'error');
CREATE TYPE change_type        AS ENUM ('added', 'removed', 'changed');
CREATE TYPE job_state          AS ENUM ('queued', 'running', 'succeeded', 'failed');
CREATE TYPE report_category    AS ENUM ('missing', 'malfunction', 'inaccessible', 'incorrect_hours', 'incorrect_location', 'other');
CREATE TYPE report_status      AS ENUM ('pending', 'accepted', 'rejected', 'resolved');
CREATE TYPE asset_kind         AS ENUM ('aed_data', 'basemap');

-- ---------------------------------------------------------------- reference data

-- Data sources and their attribution (GET /data/status).
CREATE TABLE data_source (
    id                text PRIMARY KEY,             -- 'warsaw_open_data'
    name              text NOT NULL,
    attribution       text NOT NULL,
    license_url       text,
    refresh_interval  interval NOT NULL DEFAULT interval '2 hours'
);

-- Warsaw administrative boundary: the service area for discovery, origins and coverage.
CREATE TABLE service_area (
    id          smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    name        text NOT NULL DEFAULT 'Warszawa',
    boundary    geometry(MultiPolygon, 4326) NOT NULL,
    source      text NOT NULL,
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX service_area_boundary_idx ON service_area USING gist (boundary);

CREATE TABLE district (
    id            smallserial PRIMARY KEY,
    name          text NOT NULL UNIQUE,             -- 'Mokotów', 'Praga-Północ' ... (18 districts)
    osm_relation  bigint,
    boundary      geometry(MultiPolygon, 4326)
);
CREATE INDEX district_boundary_idx ON district USING gist (boundary);

-- Polish public holidays, used together with aed_hours.holiday_policy.
CREATE TABLE public_holiday (
    on_date  date PRIMARY KEY,
    name     text NOT NULL
);

-- Only buildings that an AED was matched to (not all 184k from the city layer).
CREATE TABLE building (
    id            text PRIMARY KEY,                 -- ID_BUDYNKU from the city GeoServer layer `budynki`
    floors_above  smallint CHECK (floors_above BETWEEN 0 AND 80),
    floors_below  smallint CHECK (floors_below BETWEEN 0 AND 20),
    kind          char(1),                          -- RODZAJ: m residential, i other, t transport, h trade, b office, k education/culture/sport, s health, ...
    footprint     geometry(Geometry, 4326)
);

-- One address can hold several AEDs (a school with two devices), so addresses are their own table.
CREATE TABLE address (
    id              bigserial PRIMARY KEY,
    street_raw      text NOT NULL,                  -- as written in the SCB record: 'Rakowiecka', 'al. gen. A. Chruściela "Montera"'
    street_official text,                           -- 'ulica Rakowiecka' from the city address point, when matched
    building_no     text NOT NULL,                  -- '25/27', '2A'
    postcode        char(6) NOT NULL CHECK (postcode ~ '^[0-9]{2}-[0-9]{3}$'),
    city            text NOT NULL DEFAULT 'Warszawa',
    district_id     smallint REFERENCES district,
    official_lon    double precision,               -- city address point (punkty_adresowe)
    official_lat    double precision,
    official_location geography(Point, 4326) GENERATED ALWAYS AS (
        CASE WHEN official_lon IS NOT NULL
             THEN ST_SetSRID(ST_MakePoint(official_lon, official_lat), 4326)::geography END
    ) STORED,
    official_id     text,                           -- ID_IIP of that address point
    match           match_status NOT NULL DEFAULT 'no_match',
    match_offset_m  real,                           -- distance between the AED coordinate and the official point
    UNIQUE (street_raw, building_no, postcode),
    CHECK ((official_lon IS NULL) = (official_lat IS NULL))
);
CREATE INDEX address_district_idx ON address (district_id);

-- "ul. Rakowiecka": the SCB street field often lacks the prefix, the official name has "ulica".
CREATE FUNCTION fmt_street(raw text, official text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN official IS NOT NULL THEN regexp_replace(regexp_replace(official, '^ulica ', 'ul. '), '^aleja ', 'al. ')
        WHEN raw ~* '^(ul\.|al\.|pl\.|aleja |plac |os\.|osiedle |rondo |skwer |bulwar |park )' THEN raw
        ELSE 'ul. ' || raw
    END
$$;

ALTER TABLE address ADD COLUMN full_address text GENERATED ALWAYS AS (
    fmt_street(street_raw, street_official) || ' ' || building_no || ', ' || postcode || ' ' || city
) STORED;

-- ---------------------------------------------------------------- background jobs (GET /internal/jobs/{id})

CREATE TABLE job (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind             text NOT NULL CHECK (kind IN ('import', 'parse_hours', 'coverage', 'offline_build')),
    state            job_state NOT NULL DEFAULT 'queued',
    dedupe_key       text NOT NULL,                 -- resource + input version, e.g. 'aed:<id>:<text hash>:<parser>'
    idempotency_key  uuid,                          -- Idempotency-Key of the request that queued it
    input            jsonb NOT NULL DEFAULT '{}',
    progress         jsonb NOT NULL DEFAULT '{}',   -- counts for status endpoints
    error            text,                          -- sanitized; never raw provider/importer output
    created_at       timestamptz NOT NULL DEFAULT now(),
    started_at       timestamptz,
    finished_at      timestamptz,
    UNIQUE (kind, idempotency_key),
    CHECK ((state IN ('succeeded', 'failed')) = (finished_at IS NOT NULL))
);
-- Equivalent work that is already queued/running is reused instead of duplicated.
CREATE UNIQUE INDEX job_active_dedupe_idx ON job (kind, dedupe_key) WHERE state IN ('queued', 'running');

-- ---------------------------------------------------------------- refresh history and snapshots

CREATE TABLE refresh_run (
    id           bigserial PRIMARY KEY,
    job_id       uuid REFERENCES job,
    started_at   timestamptz NOT NULL DEFAULT now(),
    finished_at  timestamptz,
    status       text NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'ok', 'failed')),
    total        integer,
    added        integer,
    removed      integer,
    changed      integer,
    quarantined  integer,                           -- malformed rows kept out of the dataset
    llm_calls    integer NOT NULL DEFAULT 0,
    error        text
);
-- Job lock: at most one refresh runs at a time.
CREATE UNIQUE INDEX refresh_run_single_running_idx ON refresh_run ((true)) WHERE status = 'running';

-- Raw source responses. An incomplete or suspicious snapshot never removes AEDs.
CREATE TABLE source_snapshot (
    run_id             bigint PRIMARY KEY REFERENCES refresh_run ON DELETE CASCADE,
    fetched_at         timestamptz NOT NULL DEFAULT now(),
    source_updated_at  timestamptz,                 -- update metadata reported by the city, if any
    record_count       integer NOT NULL CHECK (record_count >= 0),
    sha256             text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    complete           boolean NOT NULL,            -- passed envelope/count/field validation
    payload            jsonb NOT NULL
);

-- Published dataset versions. API responses, coverage layers and offline assets carry one.
CREATE TABLE dataset_version (
    id              bigserial PRIMARY KEY,
    cause           text NOT NULL CHECK (cause IN ('import', 'override')),
    refresh_run_id  bigint REFERENCES refresh_run,
    override_id     bigint,                         -- FK added after aed_override
    published_at    timestamptz NOT NULL DEFAULT now(),
    CHECK ((cause = 'import') = (refresh_run_id IS NOT NULL)),
    CHECK ((cause = 'override') = (override_id IS NOT NULL))
);

-- ---------------------------------------------------------------- AED

CREATE TABLE aed (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id            text NOT NULL UNIQUE,      -- defibrillator_id in the SCB API
    object_name          text NOT NULL,             -- location_object_name: 'Urząd Dzielnicy Mokotów m.st. Warszawy'
    address_id           bigint NOT NULL REFERENCES address,
    lon                  double precision NOT NULL CHECK (lon BETWEEN 20.7 AND 21.4),
    lat                  double precision NOT NULL CHECK (lat BETWEEN 52.0 AND 52.5),
    location             geography(Point, 4326) NOT NULL GENERATED ALWAYS AS (
                             ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography
                         ) STORED,
    -- where exactly
    in_building          boolean NOT NULL,          -- device_location: inside (true) / outside (false) the building
    in_footprint         boolean,                   -- cross-check: the point lies inside a building footprint (NULL = not computed)
    floor                smallint CHECK (floor BETWEEN -5 AND 60),
    floor_source         floor_source,
    location_description text,                      -- 'Przy wejściu głównym, po lewej stronie' (entrance instructions shown to the user)
    building_id          text REFERENCES building,
    -- device and access
    public_access        public_access NOT NULL DEFAULT 'unknown',
    public_access_raw    text,                      -- device_public_access as given: 'Publiczny' | 'Ograniczony' | ...
    availability_raw     text,                      -- device_availability as given: 'Tak' | 'Nie' | 'Ograniczona' | free text
    access_text          text,                      -- device_access_description: original hours/access text
    access_text_hash     text NOT NULL GENERATED ALWAYS AS (md5(coalesce(access_text, ''))) STORED,
    manufacturer         text,
    has_specifications   text,                      -- device_specifications: 'Tak' | 'Nie' | 'Brak informacji'
    -- lifecycle (maintained by the refresh job)
    first_seen_at        timestamptz NOT NULL DEFAULT now(),
    last_fetched_at      timestamptz NOT NULL DEFAULT now(), -- last complete snapshot that contained the record
    source_updated_at    timestamptz,               -- when the city last changed the record, if known
    last_verified_at     timestamptz,               -- last physical/official verification; a fetch is not a verification
    missing_runs         smallint NOT NULL DEFAULT 0 CHECK (missing_runs >= 0), -- consecutive complete snapshots without the record
    removed_at           timestamptz,               -- set only after two complete snapshots confirm absence
    source_hash          text,                      -- hash of the raw API record, to detect changes cheaply
    CHECK ((floor IS NULL) = (floor_source IS NULL)),
    CHECK (removed_at IS NULL OR missing_runs >= 2)
);
CREATE INDEX aed_address_idx  ON aed (address_id);
CREATE INDEX aed_location_idx ON aed USING gist (location);
CREATE INDEX aed_active_idx   ON aed (id) WHERE removed_at IS NULL;

-- ---------------------------------------------------------------- opening hours

-- A structured schedule. origin = 'source': parsed from aed.access_text, trusted only while
-- source_text_hash matches aed.access_text_hash and review_status is validated/validated_partial.
-- origin = 'override': entered by a moderator through an 'hours' override.
CREATE TABLE aed_hours (
    id                   bigserial PRIMARY KEY,
    aed_id               uuid NOT NULL REFERENCES aed ON DELETE CASCADE,
    origin               text NOT NULL DEFAULT 'source' CHECK (origin IN ('source', 'override')),
    status               hours_status NOT NULL,
    source_text          text,                      -- the access text this parse is based on
    source_text_hash     text,                      -- md5(coalesce(source_text, '')), compared with aed.access_text_hash
    osm_hours            text,                      -- normalized, e.g. 'Mo-Fr 08:00-16:00; Sa 10:00-14:00'
    holiday_policy       holiday_policy NOT NULL DEFAULT 'unknown',
    access_conditions    text[] NOT NULL DEFAULT '{}',  -- 'ask_security', 'reception_key', ... kept apart from opening hours
    applied_source_rules text[] NOT NULL DEFAULT '{}',  -- versioned, documented source rules only ('scb_omitted_days_closed@1'); never model guesses
    evidence             text,                      -- the part of the text that supports the schedule
    parse_source         text NOT NULL,             -- availability_field | regex | llm:<model> | manual
    parser_version       text NOT NULL,
    review_status        review_status NOT NULL DEFAULT 'pending',
    note                 text,                      -- LLM remarks, e.g. holiday exceptions
    parsed_at            timestamptz NOT NULL DEFAULT now(),
    reviewed_at          timestamptz,
    reviewed_by          uuid REFERENCES auth.users,
    CHECK (origin = 'override' OR source_text_hash IS NOT NULL)
);
-- One current parsed schedule per AED; override schedules are kept with their overrides.
CREATE UNIQUE INDEX aed_hours_source_idx ON aed_hours (aed_id) WHERE origin = 'source';

-- Explicit state of every weekday. A missing row means unknown, never closed.
CREATE TABLE aed_day_state (
    hours_id  bigint NOT NULL REFERENCES aed_hours ON DELETE CASCADE,
    dow       smallint NOT NULL CHECK (dow BETWEEN 1 AND 7),
    state     day_state NOT NULL,
    PRIMARY KEY (hours_id, dow),
    UNIQUE (hours_id, dow, state)
);

-- Weekly opening intervals; only allowed on days whose state is open_intervals.
CREATE TABLE aed_schedule (
    hours_id   bigint NOT NULL,
    dow        smallint NOT NULL,
    state      day_state NOT NULL DEFAULT 'open_intervals' CHECK (state = 'open_intervals'),
    start_min  smallint NOT NULL CHECK (start_min BETWEEN 0 AND 1439),
    end_min    smallint NOT NULL CHECK (end_min BETWEEN 1 AND 1440),
    PRIMARY KEY (hours_id, dow, start_min),
    FOREIGN KEY (hours_id, dow, state) REFERENCES aed_day_state (hours_id, dow, state) ON DELETE CASCADE,
    CHECK (end_min > start_min),
    EXCLUDE USING gist (hours_id WITH =, dow WITH =, int4range(start_min, end_min) WITH &&)
);

-- Date exceptions override weekly hours and holiday policy.
CREATE TABLE aed_hours_exception (
    hours_id  bigint NOT NULL REFERENCES aed_hours ON DELETE CASCADE,
    on_date   date NOT NULL,
    state     day_state NOT NULL,
    note      text,
    PRIMARY KEY (hours_id, on_date),
    UNIQUE (hours_id, on_date, state)
);

CREATE TABLE aed_exception_interval (
    hours_id   bigint NOT NULL,
    on_date    date NOT NULL,
    state      day_state NOT NULL DEFAULT 'open_intervals' CHECK (state = 'open_intervals'),
    start_min  smallint NOT NULL CHECK (start_min BETWEEN 0 AND 1439),
    end_min    smallint NOT NULL CHECK (end_min BETWEEN 1 AND 1440),
    PRIMARY KEY (hours_id, on_date, start_min),
    FOREIGN KEY (hours_id, on_date, state) REFERENCES aed_hours_exception (hours_id, on_date, state) ON DELETE CASCADE,
    CHECK (end_min > start_min),
    EXCLUDE USING gist (hours_id WITH =, on_date WITH =, int4range(start_min, end_min) WITH &&)
);

-- Cache of LLM answers. Keyed by text hash and parser version so a new prompt/model re-parses.
CREATE TABLE hours_cache (
    source_text_hash  text NOT NULL,
    parser_version    text NOT NULL,
    source_text       text NOT NULL,
    status            hours_status NOT NULL,
    schedule          jsonb NOT NULL,
    source            text NOT NULL,
    model             text,
    note              text,
    created_at        timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (source_text_hash, parser_version)
);

-- ---------------------------------------------------------------- photos

CREATE TABLE aed_photo (
    id               serial PRIMARY KEY,
    aed_id           uuid NOT NULL REFERENCES aed ON DELETE CASCADE,
    file_name        text NOT NULL,                 -- original, kept private (contains EXIF)
    public_file_name text,                          -- resized copy without EXIF: the only one the app may serve
    sha256           text,
    width            integer,
    height           integer,
    taken_at         timestamptz,
    camera_make      text,
    exif_has_gps     boolean NOT NULL DEFAULT false -- EXIF GPS can be compared with the record coordinate (audit)
);
CREATE INDEX aed_photo_aed_idx ON aed_photo (aed_id);

-- ---------------------------------------------------------------- moderators

-- Server-verified moderator/admin role. Phone verification never grants it.
CREATE TABLE staff_member (
    user_id     uuid PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
    role        text NOT NULL CHECK (role IN ('moderator', 'admin')),
    granted_by  uuid REFERENCES auth.users,
    granted_at  timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------- reports (ENDPOINTS.md §4)

-- OTP challenge with the report draft it is bound to. The phone number stays in Supabase Auth
-- (auth.users); this table only references the identity.
CREATE TABLE otp_challenge (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),   -- challenge_id returned to the client
    user_id          uuid NOT NULL REFERENCES auth.users,
    aed_id           uuid NOT NULL REFERENCES aed,
    category         report_category NOT NULL,
    description      text NOT NULL CHECK (char_length(btrim(description)) BETWEEN 10 AND 2000),
    created_at       timestamptz NOT NULL DEFAULT now(),
    last_sent_at     timestamptz NOT NULL DEFAULT now(),
    expires_at       timestamptz NOT NULL,
    send_count       smallint NOT NULL DEFAULT 1 CHECK (send_count BETWEEN 1 AND 5),
    verify_attempts  smallint NOT NULL DEFAULT 0 CHECK (verify_attempts BETWEEN 0 AND 5),
    verified_at      timestamptz,
    superseded_at    timestamptz,                   -- a newer challenge or resend invalidated this one
    CHECK (expires_at > last_sent_at AND expires_at <= last_sent_at + interval '5 minutes')
);
CREATE INDEX otp_challenge_cleanup_idx ON otp_challenge (expires_at) WHERE verified_at IS NULL;

-- Single-use report_token issued after OTP verification. Only the token hash is stored.
CREATE TABLE report_authorization (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id     uuid NOT NULL UNIQUE REFERENCES otp_challenge,
    token_hash       text NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'), -- sha256 of the report_token
    created_at       timestamptz NOT NULL DEFAULT now(),
    expires_at       timestamptz NOT NULL,
    consumed_at      timestamptz,
    idempotency_key  uuid,                          -- Idempotency-Key of the submission that consumed it
    CHECK (expires_at > created_at AND expires_at <= created_at + interval '10 minutes'),
    CHECK ((consumed_at IS NULL) = (idempotency_key IS NULL))
);

CREATE TABLE report (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    authorization_id  uuid NOT NULL UNIQUE REFERENCES report_authorization,
    aed_id            uuid NOT NULL REFERENCES aed,
    category          report_category NOT NULL,
    description       text NOT NULL CHECK (char_length(btrim(description)) BETWEEN 10 AND 2000),
    reporter_id       uuid NOT NULL REFERENCES auth.users, -- internal reporter reference; no phone number here
    idempotency_key   uuid NOT NULL,
    status            report_status NOT NULL DEFAULT 'pending',
    version           integer NOT NULL DEFAULT 1,  -- expected_version for moderation
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX report_queue_idx ON report (status, created_at);
CREATE INDEX report_aed_idx   ON report (aed_id);

CREATE TABLE report_moderation_event (
    id            bigserial PRIMARY KEY,
    report_id     uuid NOT NULL REFERENCES report ON DELETE CASCADE,
    from_status   report_status NOT NULL,
    to_status     report_status NOT NULL,
    reason        text NOT NULL CHECK (btrim(reason) <> ''),
    moderator_id  uuid NOT NULL REFERENCES auth.users,
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX report_moderation_event_report_idx ON report_moderation_event (report_id, created_at);

-- ---------------------------------------------------------------- reviewed overrides (ENDPOINTS.md §8)

-- Reviewed corrections, kept apart from imported data so refreshes never erase them.
-- Content is immutable: revoke and create a replacement. At most one active override per
-- AED and type at any time (overlaps fail with exclusion_violation -> 409 override_conflict).
--   operational_status  value {"operational_status": "unknown" | "confirmed_unavailable" | "confirmed_operational"}
--   access              value {"public_access": "public" | "restricted" | "unknown", "access_instructions"?: text}
--   coordinates         value {"lon": number, "lat": number}
--   hours               value = the submitted schedule JSON; hours_id = its materialized aed_hours row
CREATE TABLE aed_override (
    id             bigserial PRIMARY KEY,
    aed_id         uuid NOT NULL REFERENCES aed ON DELETE CASCADE,
    type           text NOT NULL CHECK (type IN ('operational_status', 'access', 'coordinates', 'hours')),
    value          jsonb NOT NULL CHECK (jsonb_typeof(value) = 'object'),
    hours_id       bigint REFERENCES aed_hours,
    reason         text NOT NULL CHECK (btrim(reason) <> ''),
    report_id      uuid REFERENCES report,
    created_by     uuid NOT NULL REFERENCES auth.users,
    created_at     timestamptz NOT NULL DEFAULT now(),
    valid_from     timestamptz NOT NULL DEFAULT now(),
    valid_until    timestamptz,
    version        integer NOT NULL DEFAULT 1,     -- expected_version for revocation
    revoked_at     timestamptz,
    revoked_by     uuid REFERENCES auth.users,
    revoke_reason  text,
    CHECK (valid_until IS NULL OR valid_until > valid_from),
    CHECK ((revoked_at IS NULL) = (revoked_by IS NULL) AND (revoked_at IS NULL) = (revoke_reason IS NULL)),
    CHECK ((type = 'hours') = (hours_id IS NOT NULL)),
    CHECK (type <> 'operational_status'
           OR value->>'operational_status' IN ('unknown', 'confirmed_unavailable', 'confirmed_operational')),
    CHECK (type <> 'access'
           OR (value->>'public_access' IN ('public', 'restricted', 'unknown')
               AND jsonb_typeof(coalesce(value->'access_instructions', '""')) = 'string')),
    CHECK (type <> 'coordinates'
           OR (jsonb_typeof(value->'lon') = 'number' AND jsonb_typeof(value->'lat') = 'number'
               AND (value->>'lon')::float8 BETWEEN 20.7 AND 21.4
               AND (value->>'lat')::float8 BETWEEN 52.0 AND 52.5)),
    EXCLUDE USING gist (aed_id WITH =, type WITH =, tstzrange(valid_from, valid_until) WITH &&)
        WHERE (revoked_at IS NULL)
);
CREATE INDEX aed_override_aed_idx ON aed_override (aed_id) WHERE revoked_at IS NULL;

ALTER TABLE dataset_version
    ADD FOREIGN KEY (override_id) REFERENCES aed_override;

-- ---------------------------------------------------------------- OpenStreetMap layer
-- Cross-check only; Warsaw Open Data stays the source of truth. OSM data is ODbL: attribute it.

CREATE TABLE osm_aed (
    osm_id         bigint NOT NULL,
    osm_type       text NOT NULL CHECK (osm_type IN ('node', 'way')),
    lon            double precision NOT NULL,
    lat            double precision NOT NULL,
    location       geography(Point, 4326) NOT NULL GENERATED ALWAYS AS (
                       ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography
                   ) STORED,
    level          smallint,
    opening_hours  text,
    access         text,
    indoor         boolean,
    operator       text,
    tags           jsonb NOT NULL DEFAULT '{}',
    matched_aed_id uuid REFERENCES aed ON DELETE SET NULL,  -- city AED within ~50 m, if any
    match_dist_m   real,
    fetched_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (osm_type, osm_id)
);
CREATE INDEX osm_aed_location_idx ON osm_aed USING gist (location);

-- ---------------------------------------------------------------- audit

CREATE TABLE audit_flag (
    id          bigserial PRIMARY KEY,
    aed_id      uuid NOT NULL REFERENCES aed ON DELETE CASCADE,
    code        text NOT NULL,                      -- see list below
    severity    flag_severity NOT NULL DEFAULT 'warning',
    detail      text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    UNIQUE (aed_id, code)
);
-- Codes used so far:
--   247_indoors_unstaffed     24/7 flag, indoors, not a staffed building (school, library ...): verify with SCB
--   247_but_limited_text      24/7 flag but the hours text lists limited hours
--   coord_far_from_address    AED coordinate is > 100 m from the official point of its own address
--   address_no_match          street + number not found among official address points
--   outdoor_in_footprint      flagged "outside" but inside a building footprint (e.g. external staircase)
--   hours_unknown             hours could not be determined (relative text, season, school term)
--   hours_llm                 hours came from the LLM, check against the raw text
--   detail_request_500        the per-device API call fails (id 2487)
--   duplicate_coords          several AEDs share exactly the same coordinate

CREATE TABLE aed_change (
    run_id   bigint NOT NULL REFERENCES refresh_run ON DELETE CASCADE,
    aed_id   uuid NOT NULL,                         -- no FK: removed devices stay in the history
    kind     change_type NOT NULL,
    before   jsonb,
    after    jsonb,
    PRIMARY KEY (run_id, aed_id)
);

-- ---------------------------------------------------------------- coverage (ENDPOINTS.md §5)

CREATE TABLE population_cell (
    code        text PRIMARY KEY,                   -- GUS grid code, 1 km cell
    lon         double precision NOT NULL,          -- cell centre
    lat         double precision NOT NULL,
    residents   integer NOT NULL,
    res_0_14    integer,
    res_15_64   integer,
    res_65_plus integer
);

CREATE TABLE coverage_layer (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),   -- layer_id
    scenario            text NOT NULL CHECK (scenario IN ('all_public', 'available_at', 'always_open')),
    threshold_m         smallint NOT NULL CHECK (threshold_m BETWEEN 100 AND 2000),
    grid_size_m         smallint NOT NULL DEFAULT 250,
    evaluated_at        timestamptz NOT NULL,
    valid_until         timestamptz,                -- next schedule/override boundary for available_at
    dataset_version_id  bigint NOT NULL REFERENCES dataset_version,
    status              text NOT NULL DEFAULT 'processing' CHECK (status IN ('processing', 'ready', 'failed')),
    job_id              uuid REFERENCES job,
    computed_at         timestamptz,
    retired_at          timestamptz,                -- requests for a retired layer get 410 layer_expired
    CHECK ((status = 'ready') = (computed_at IS NOT NULL))
);
CREATE INDEX coverage_layer_lookup_idx ON coverage_layer (scenario, threshold_m, dataset_version_id, evaluated_at DESC)
    WHERE retired_at IS NULL;

CREATE TABLE coverage_region (
    layer_id              uuid NOT NULL REFERENCES coverage_layer ON DELETE CASCADE,
    region_id             text NOT NULL,            -- grid cell id
    cell                  geometry(Polygon, 4326) NOT NULL,
    representative_point  geometry(Point, 4326) NOT NULL,
    nearest_aed_id        uuid REFERENCES aed,
    nearest_distance_m    real,
    eligible_aed_count    integer NOT NULL CHECK (eligible_aed_count >= 0),
    coverage_status       text NOT NULL CHECK (coverage_status IN ('covered', 'gap', 'no_known_eligible_aed')),
    PRIMARY KEY (layer_id, region_id),
    CHECK ((coverage_status = 'no_known_eligible_aed') = (nearest_aed_id IS NULL)),
    CHECK ((nearest_aed_id IS NULL) = (nearest_distance_m IS NULL))
);
CREATE INDEX coverage_region_cell_idx ON coverage_region USING gist (cell);

CREATE TABLE coverage_hour (
    basis        text NOT NULL CHECK (basis IN ('address_points', 'population_cells')),
    include_osm  boolean NOT NULL DEFAULT false,
    radius_m     smallint NOT NULL,
    dow          smallint NOT NULL CHECK (dow BETWEEN 1 AND 7),
    hour         smallint NOT NULL CHECK (hour BETWEEN 0 AND 23),
    available    integer NOT NULL,                  -- AEDs open at that hour (unknown ones excluded)
    covered      real NOT NULL CHECK (covered BETWEEN 0 AND 1),
    computed_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (basis, include_osm, radius_m, dow, hour)
);

CREATE TABLE relocation_rank (
    radius_m       smallint NOT NULL,
    rank           smallint NOT NULL,
    aed_id         uuid NOT NULL REFERENCES aed ON DELETE CASCADE,
    gain_pp        real NOT NULL,                   -- night coverage gained if this AED became a 24/7 outdoor cabinet, percentage points
    cum_night_cov  real NOT NULL,                   -- cumulative night coverage after taking ranks 1..rank
    computed_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (radius_m, rank)
);

-- Participatory budget projects about AEDs. Author names are NOT stored (personal data).
CREATE TABLE bo_project (
    id              integer PRIMARY KEY,
    edition         text NOT NULL,                  -- 'na rok 2024'
    title           text NOT NULL,
    short_desc      text,
    cost_pln        numeric(12, 2),
    lon             double precision,
    lat             double precision,
    district        text,
    categories      text[] NOT NULL DEFAULT '{}',
    is_aed_related  boolean NOT NULL DEFAULT false,
    url             text
);

-- ---------------------------------------------------------------- offline packages (ENDPOINTS.md §6)

-- Downloadable areas: all of Warsaw and supported districts.
CREATE TABLE offline_region (
    id           text PRIMARY KEY,                  -- 'warszawa', 'mokotow'
    name         text NOT NULL,
    bounds       geometry(Polygon, 4326) NOT NULL,
    district_id  smallint REFERENCES district,
    sort_order   smallint NOT NULL DEFAULT 0
);

-- Immutable, versioned files in Storage. Basemap and AED data are versioned independently.
CREATE TABLE offline_asset (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    region_id           text NOT NULL REFERENCES offline_region,
    kind                asset_kind NOT NULL,
    version             text NOT NULL,
    format              text NOT NULL,              -- 'pmtiles', 'json.gz', ...
    storage_path        text NOT NULL UNIQUE,
    size_bytes          bigint NOT NULL CHECK (size_bytes > 0),
    sha256              text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    dataset_version_id  bigint REFERENCES dataset_version,
    created_at          timestamptz NOT NULL DEFAULT now(),
    available_until     timestamptz,                -- end of the retention window; NULL while current
    UNIQUE (region_id, kind, version),
    CHECK ((kind = 'aed_data') = (dataset_version_id IS NOT NULL))
);

-- A manifest: one basemap asset + one AED asset, published only after both are ready.
CREATE TABLE offline_release (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    region_id           text NOT NULL REFERENCES offline_region,
    version             integer NOT NULL CHECK (version > 0),
    schema_version      smallint NOT NULL,
    basemap_asset_id    uuid NOT NULL REFERENCES offline_asset,
    aed_asset_id        uuid NOT NULL REFERENCES offline_asset,
    dataset_version_id  bigint NOT NULL REFERENCES dataset_version,
    attribution         text NOT NULL,
    build_job_id        uuid REFERENCES job,
    generated_at        timestamptz NOT NULL DEFAULT now(),
    published_at        timestamptz,
    superseded_at       timestamptz,
    UNIQUE (region_id, version),
    CHECK (superseded_at IS NULL OR published_at IS NOT NULL)
);
-- At most one current published release per region.
CREATE UNIQUE INDEX offline_release_current_idx ON offline_release (region_id)
    WHERE published_at IS NOT NULL AND superseded_at IS NULL;

-- ---------------------------------------------------------------- helpers

CREATE FUNCTION dist_m(lat1 double precision, lon1 double precision, lat2 double precision, lon2 double precision)
RETURNS double precision LANGUAGE sql IMMUTABLE AS $$
    SELECT 2 * 6371000 * asin(sqrt(
        power(sin(radians(lat2 - lat1) / 2), 2) +
        cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2)))
$$;

CREATE FUNCTION floor_label(f smallint) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN f IS NULL THEN NULL WHEN f = 0 THEN 'parter' WHEN f < 0 THEN 'poziom ' || f ELSE f || '. piętro' END
$$;

-- SECURITY DEFINER: dataset_version itself is private.
CREATE FUNCTION current_dataset_version() RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT max(id) FROM public.dataset_version
$$;

CREATE FUNCTION is_inside_warsaw(p_lat double precision, p_lon double precision) RETURNS boolean
LANGUAGE sql STABLE SET search_path = public, extensions AS $$
    SELECT EXISTS (
        SELECT 1 FROM service_area
        WHERE ST_Covers(boundary, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326))
    )
$$;

CREATE FUNCTION is_staff(p_user_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT EXISTS (SELECT 1 FROM public.staff_member WHERE user_id = p_user_id)
$$;

-- Effective values after active overrides, plus derived audit state.
-- SECURITY DEFINER so public reads get the result without access to overrides or flags.
CREATE FUNCTION aed_effective_state(p_aed_id uuid)
RETURNS TABLE (
    lon                  double precision,
    lat                  double precision,
    public_access        public_access,
    access_instructions  text,
    operational_status   operational_status,
    hours_id             bigint,
    hours_overridden     boolean,
    has_open_flags       boolean
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    WITH active AS (
        SELECT o.type, o.value, o.hours_id FROM public.aed_override o
        WHERE o.aed_id = p_aed_id
          AND o.revoked_at IS NULL
          AND o.valid_from <= now()
          AND (o.valid_until IS NULL OR o.valid_until > now())
    )
    SELECT
        coalesce((c.value->>'lon')::float8, a.lon),
        coalesce((c.value->>'lat')::float8, a.lat),
        coalesce((ac.value->>'public_access')::public.public_access, a.public_access),
        coalesce(ac.value->>'access_instructions', a.location_description),
        coalesce((os.value->>'operational_status')::public.operational_status, 'unknown'),
        coalesce(hr.hours_id, sh.id),
        hr.hours_id IS NOT NULL,
        EXISTS (SELECT 1 FROM public.audit_flag f
                WHERE f.aed_id = p_aed_id AND f.resolved_at IS NULL AND f.severity <> 'info')
    FROM public.aed a
    LEFT JOIN active c  ON c.type = 'coordinates'
    LEFT JOIN active ac ON ac.type = 'access'
    LEFT JOIN active os ON os.type = 'operational_status'
    LEFT JOIN active hr ON hr.type = 'hours'
    LEFT JOIN public.aed_hours sh ON sh.aed_id = a.id AND sh.origin = 'source'
    WHERE a.id = p_aed_id
$$;

-- Effective rule for one local calendar day of a schedule:
-- date exception > 24/7 > holiday policy > weekly hours. `open` merges adjacent intervals.
CREATE FUNCTION aed_day(p_hours_id bigint, p_day date)
RETURNS TABLE (state day_state, reason text, open nummultirange)
LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE
    h aed_hours;
    v_state day_state;
BEGIN
    SELECT * INTO h FROM aed_hours WHERE id = p_hours_id;

    SELECT e.state INTO v_state FROM aed_hours_exception e WHERE e.hours_id = p_hours_id AND e.on_date = p_day;
    IF FOUND THEN
        RETURN QUERY SELECT v_state, 'date_exception',
            coalesce((SELECT range_agg(numrange(i.start_min, i.end_min, '[)')) FROM aed_exception_interval i
                      WHERE i.hours_id = p_hours_id AND i.on_date = p_day), '{}'::nummultirange);
        RETURN;
    END IF;

    IF h.status = '24/7' THEN
        RETURN QUERY SELECT 'open_intervals'::day_state, 'always_open', nummultirange(numrange(0, 1440, '[)'));
        RETURN;
    END IF;

    IF EXISTS (SELECT 1 FROM public_holiday WHERE on_date = p_day) AND h.holiday_policy <> 'regular_hours' THEN
        RETURN QUERY SELECT
            CASE h.holiday_policy WHEN 'closed' THEN 'closed'::day_state ELSE 'unknown'::day_state END,
            CASE h.holiday_policy WHEN 'closed' THEN 'holiday_closed' ELSE 'holiday_hours_unknown' END,
            '{}'::nummultirange;
        RETURN;
    END IF;

    SELECT d.state INTO v_state FROM aed_day_state d
    WHERE d.hours_id = p_hours_id AND d.dow = extract(isodow FROM p_day);
    RETURN QUERY SELECT
        coalesce(v_state, 'unknown'),
        CASE WHEN v_state IS NULL OR v_state = 'unknown' THEN 'day_unknown' ELSE 'weekly_hours' END,
        coalesce((SELECT range_agg(numrange(s.start_min, s.end_min, '[)')) FROM aed_schedule s
                  WHERE s.hours_id = p_hours_id AND s.dow = extract(isodow FROM p_day)), '{}'::nummultirange);
END
$$;

-- Availability over [p_from, p_until] (a single moment when p_until is NULL).
--   status          state at p_from: open / closed / unknown
--   covers_interval true only when known opening hours cover the whole window
-- Used by "find" with p_until = arrival + access buffer.
CREATE FUNCTION aed_availability(p_aed_id uuid, p_from timestamptz DEFAULT now(), p_until timestamptz DEFAULT NULL)
RETURNS TABLE (status availability_state, covers_interval boolean, reasons text[])
LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE
    v_until    timestamptz := coalesce(p_until, p_from);
    v_from_l   timestamp := p_from AT TIME ZONE 'Europe/Warsaw';
    v_until_l  timestamp := coalesce(p_until, p_from) AT TIME ZONE 'Europe/Warsaw';
    v_hours_id bigint;
    v_override boolean;
    h          aed_hours;
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

    SELECT e.hours_id, e.hours_overridden INTO v_hours_id, v_override FROM aed_effective_state(p_aed_id) e;
    SELECT * INTO h FROM aed_hours WHERE id = v_hours_id;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'unknown'::availability_state, false, ARRAY['no_hours']; RETURN;
    END IF;
    IF NOT v_override THEN
        IF h.source_text_hash IS DISTINCT FROM (SELECT access_text_hash FROM aed WHERE id = p_aed_id) THEN
            RETURN QUERY SELECT 'unknown'::availability_state, false, ARRAY['hours_outdated']; RETURN;
        END IF;
        IF h.review_status NOT IN ('validated', 'validated_partial') THEN
            RETURN QUERY SELECT 'unknown'::availability_state, false, ARRAY['hours_not_validated']; RETURN;
        END IF;
    END IF;
    IF h.status = 'unknown' THEN
        RETURN QUERY SELECT 'unknown'::availability_state, false, ARRAY['hours_unknown']; RETURN;
    END IF;

    v_cursor := extract(epoch FROM v_from_l::time) / 60;
    LOOP
        SELECT * INTO d FROM aed_day(v_hours_id, v_day);

        IF d.state <> 'open_intervals' THEN
            IF v_first THEN
                RETURN QUERY SELECT
                    CASE d.state WHEN 'closed' THEN 'closed'::availability_state ELSE 'unknown'::availability_state END,
                    false, ARRAY[d.reason];
            ELSE
                RETURN QUERY SELECT 'open'::availability_state, false, ARRAY['next_day_' || d.reason];
            END IF;
            RETURN;
        END IF;

        SELECT upper(r) INTO v_end FROM unnest(d.open) r WHERE r @> v_cursor;
        IF v_end IS NULL THEN
            IF v_first THEN
                RETURN QUERY SELECT 'closed'::availability_state, false, ARRAY['outside_hours'];
            ELSE
                RETURN QUERY SELECT 'open'::availability_state, false, ARRAY['closes_within_window'];
            END IF;
            RETURN;
        END IF;

        -- Window ends today, or exactly at midnight after an interval that runs to 24:00.
        IF (v_until_l::date = v_day AND extract(epoch FROM v_until_l::time) / 60 <= v_end)
           OR (v_until_l = (v_day + 1)::timestamp AND v_end = 1440) THEN
            RETURN QUERY SELECT 'open'::availability_state, true, ARRAY[d.reason]; RETURN;
        END IF;
        IF v_end < 1440 THEN
            RETURN QUERY SELECT 'open'::availability_state, false, ARRAY['closes_within_window']; RETURN;
        END IF;

        v_day := v_day + 1;
        v_cursor := 0;
        v_first := false;
    END LOOP;
END
$$;

-- Is the AED open at a moment in time? TRUE / FALSE, or NULL when its hours are unknown.
CREATE FUNCTION aed_is_open(p_aed_id uuid, p_at timestamptz DEFAULT now()) RETURNS boolean
LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT CASE status WHEN 'open' THEN true WHEN 'closed' THEN false END
    FROM aed_availability(p_aed_id, p_at)
$$;

-- Candidates for nearby discovery, ordered by straight-line distance from the effective location.
-- SECURITY DEFINER because coordinate overrides are private.
CREATE FUNCTION aeds_nearby(
    p_lat double precision,
    p_lon double precision,
    p_radius_m integer DEFAULT 2000,
    p_limit integer DEFAULT 20,
    p_exclude uuid[] DEFAULT '{}'
)
RETURNS TABLE (id uuid, distance_m double precision)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    WITH o AS (
        SELECT extensions.ST_SetSRID(extensions.ST_MakePoint(p_lon, p_lat), 4326)::extensions.geography AS g,
               least(p_radius_m, 20000) AS r
    ),
    pool AS (
        SELECT a.id FROM public.aed a, o
        WHERE a.removed_at IS NULL AND extensions.ST_DWithin(a.location, o.g, o.r)
        UNION
        SELECT ov.aed_id FROM public.aed_override ov
        WHERE ov.type = 'coordinates' AND ov.revoked_at IS NULL
          AND ov.valid_from <= now() AND (ov.valid_until IS NULL OR ov.valid_until > now())
    ),
    measured AS (
        SELECT p.id,
               extensions.ST_Distance(
                   extensions.ST_SetSRID(extensions.ST_MakePoint(e.lon, e.lat), 4326)::extensions.geography, o.g
               ) AS distance_m,
               o.r
        FROM pool p
        JOIN public.aed a ON a.id = p.id AND a.removed_at IS NULL
        CROSS JOIN o
        CROSS JOIN LATERAL public.aed_effective_state(p.id) e
        WHERE NOT (p.id = ANY (p_exclude))
    )
    SELECT id, distance_m FROM measured
    WHERE distance_m <= r
    ORDER BY distance_m
    LIMIT least(p_limit, 100)
$$;

-- ---------------------------------------------------------------- report submission and moderation
-- Called by the Edge Functions with the service role; never exposed to clients.
-- Errors are raised as messages the API maps to codes: report_authorization_invalid (401),
-- report_authorization_expired (410), authorization_used (409), version_conflict (409),
-- invalid_transition (409), not_moderator (403), report_not_found / override_not_found (404).

-- POST /reports: consumes the authorization atomically and stores its bound draft.
-- Repeating a successful request with the same Idempotency-Key within 24 h returns the receipt.
CREATE FUNCTION submit_report(p_token_hash text, p_idempotency_key uuid)
RETURNS TABLE (report_id uuid, status report_status, submitted_at timestamptz, replayed boolean)
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
    v_auth   report_authorization;
    v_ch     otp_challenge;
    v_report report;
BEGIN
    SELECT * INTO v_auth FROM report_authorization WHERE token_hash = p_token_hash FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'report_authorization_invalid';
    END IF;

    IF v_auth.consumed_at IS NOT NULL THEN
        IF v_auth.idempotency_key = p_idempotency_key AND v_auth.consumed_at > now() - interval '24 hours' THEN
            SELECT * INTO v_report FROM report WHERE authorization_id = v_auth.id;
            RETURN QUERY SELECT v_report.id, v_report.status, v_report.created_at, true;
            RETURN;
        END IF;
        RAISE EXCEPTION 'authorization_used';
    END IF;
    IF v_auth.expires_at <= now() THEN
        RAISE EXCEPTION 'report_authorization_expired';
    END IF;

    SELECT * INTO v_ch FROM otp_challenge WHERE id = v_auth.challenge_id;
    UPDATE report_authorization SET consumed_at = now(), idempotency_key = p_idempotency_key WHERE id = v_auth.id;
    INSERT INTO report (authorization_id, aed_id, category, description, reporter_id, idempotency_key)
    VALUES (v_auth.id, v_ch.aed_id, v_ch.category, btrim(v_ch.description), v_ch.user_id, p_idempotency_key)
    RETURNING * INTO v_report;
    RETURN QUERY SELECT v_report.id, v_report.status, v_report.created_at, false;
END
$$;

-- PATCH /admin/reports/{id}. Accepting a report does not change the AED; that needs an override.
CREATE FUNCTION moderate_report(
    p_report_id uuid,
    p_status report_status,
    p_reason text,
    p_expected_version integer,
    p_moderator uuid
) RETURNS integer
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
    v_report report;
BEGIN
    IF NOT is_staff(p_moderator) THEN
        RAISE EXCEPTION 'not_moderator';
    END IF;
    SELECT * INTO v_report FROM report WHERE id = p_report_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'report_not_found';
    END IF;
    IF v_report.version <> p_expected_version THEN
        RAISE EXCEPTION 'version_conflict';
    END IF;
    IF (v_report.status, p_status) NOT IN (('pending', 'accepted'), ('pending', 'rejected'), ('accepted', 'resolved')) THEN
        RAISE EXCEPTION 'invalid_transition';
    END IF;

    UPDATE report SET status = p_status, version = version + 1, updated_at = now() WHERE id = p_report_id;
    INSERT INTO report_moderation_event (report_id, from_status, to_status, reason, moderator_id)
    VALUES (p_report_id, v_report.status, p_status, p_reason, p_moderator);
    RETURN v_report.version + 1;
END
$$;

-- PATCH /admin/aeds/{id}/overrides/{override_id}: revoke, keeping the audit history.
CREATE FUNCTION revoke_override(p_override_id bigint, p_reason text, p_expected_version integer, p_moderator uuid)
RETURNS integer
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
    v_override aed_override;
BEGIN
    SELECT * INTO v_override FROM aed_override WHERE id = p_override_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'override_not_found';
    END IF;
    IF v_override.version <> p_expected_version OR v_override.revoked_at IS NOT NULL THEN
        RAISE EXCEPTION 'version_conflict';
    END IF;
    UPDATE aed_override
    SET revoked_at = now(), revoked_by = p_moderator, revoke_reason = p_reason, version = version + 1
    WHERE id = p_override_id;
    RETURN v_override.version + 1;
END
$$;

-- Overrides: only staff create/revoke, content is immutable, and every change publishes a new dataset version.
CREATE FUNCTION aed_override_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NOT is_staff(NEW.created_by) THEN
            RAISE EXCEPTION 'not_moderator';
        END IF;
    ELSE
        IF OLD.revoked_at IS NOT NULL OR NEW.revoked_at IS NULL THEN
            RAISE EXCEPTION 'override_immutable';
        END IF;
        IF (NEW.aed_id, NEW.type, NEW.value, NEW.hours_id, NEW.reason, NEW.report_id,
            NEW.created_by, NEW.created_at, NEW.valid_from, NEW.valid_until)
           IS DISTINCT FROM
           (OLD.aed_id, OLD.type, OLD.value, OLD.hours_id, OLD.reason, OLD.report_id,
            OLD.created_by, OLD.created_at, OLD.valid_from, OLD.valid_until) THEN
            RAISE EXCEPTION 'override_immutable';
        END IF;
        IF NOT is_staff(NEW.revoked_by) THEN
            RAISE EXCEPTION 'not_moderator';
        END IF;
    END IF;
    RETURN NEW;
END
$$;

CREATE FUNCTION aed_override_publish() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    INSERT INTO dataset_version (cause, override_id) VALUES ('override', NEW.id);
    RETURN NULL;
END
$$;

CREATE TRIGGER aed_override_guard BEFORE INSERT OR UPDATE ON aed_override
    FOR EACH ROW EXECUTE FUNCTION aed_override_guard();
CREATE TRIGGER aed_override_publish AFTER INSERT OR UPDATE ON aed_override
    FOR EACH ROW EXECUTE FUNCTION aed_override_publish();
-- Deleting an override fails: its dataset_version row references it.

-- ---------------------------------------------------------------- what the app reads

-- Effective (override-applied) public data. nav_lon/nav_lat: the official address point when we
-- have one, else the AED coordinate; routing to the device itself uses lon/lat.
CREATE VIEW aed_public WITH (security_invoker = true) AS
SELECT
    a.id,
    a.source_id,
    e.lon,
    e.lat,
    a.object_name,
    ad.full_address,
    fmt_street(ad.street_raw, ad.street_official)          AS street,
    ad.building_no,
    ad.postcode,
    ad.city,
    d.name                                                 AS district,
    a.in_building,
    a.floor,
    floor_label(a.floor)                                   AS floor_label,
    a.floor_source,
    e.access_instructions,
    e.public_access,
    e.operational_status,
    a.manufacturer,
    h.status                                               AS hours_status,
    h.review_status                                        AS hours_review_status,
    e.hours_overridden,
    h.osm_hours,
    h.access_conditions,
    a.access_text                                          AS hours_raw,
    aed_is_open(a.id)                                      AS open_now,
    b.floors_above                                         AS building_floors,
    a.last_fetched_at,
    a.source_updated_at,
    a.last_verified_at,
    coalesce(ad.official_lon, e.lon)                       AS nav_lon,
    coalesce(ad.official_lat, e.lat)                       AS nav_lat,
    'https://www.google.com/maps/search/?api=1&query='
        || coalesce(ad.official_lat, e.lat) || ',' || coalesce(ad.official_lon, e.lon)             AS google_maps_url,
    'https://www.google.com/maps/dir/?api=1&travelmode=walking&destination='
        || coalesce(ad.official_lat, e.lat) || ',' || coalesce(ad.official_lon, e.lon)             AS google_directions_url,
    'https://www.openstreetmap.org/?mlat=' || coalesce(ad.official_lat, e.lat)
        || '&mlon=' || coalesce(ad.official_lon, e.lon)
        || '#map=19/' || coalesce(ad.official_lat, e.lat) || '/' || coalesce(ad.official_lon, e.lon) AS osm_url,
    'https://maps.apple.com/?ll=' || coalesce(ad.official_lat, e.lat) || ',' || coalesce(ad.official_lon, e.lon) AS apple_maps_url,
    'geo:' || coalesce(ad.official_lat, e.lat) || ',' || coalesce(ad.official_lon, e.lon) || '?z=19' AS geo_uri,
    e.has_open_flags
FROM aed a
JOIN address ad       ON ad.id = a.address_id
LEFT JOIN district d  ON d.id = ad.district_id
CROSS JOIN LATERAL aed_effective_state(a.id) e
LEFT JOIN aed_hours h ON h.id = e.hours_id
LEFT JOIN building b  ON b.id = a.building_id
WHERE a.removed_at IS NULL;

-- ---------------------------------------------------------------- row level security and grants

ALTER TABLE data_source             ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_area            ENABLE ROW LEVEL SECURITY;
ALTER TABLE district                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public_holiday          ENABLE ROW LEVEL SECURITY;
ALTER TABLE building                ENABLE ROW LEVEL SECURITY;
ALTER TABLE address                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE job                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE refresh_run             ENABLE ROW LEVEL SECURITY;
ALTER TABLE source_snapshot         ENABLE ROW LEVEL SECURITY;
ALTER TABLE dataset_version         ENABLE ROW LEVEL SECURITY;
ALTER TABLE aed                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE aed_hours               ENABLE ROW LEVEL SECURITY;
ALTER TABLE aed_day_state           ENABLE ROW LEVEL SECURITY;
ALTER TABLE aed_schedule            ENABLE ROW LEVEL SECURITY;
ALTER TABLE aed_hours_exception     ENABLE ROW LEVEL SECURITY;
ALTER TABLE aed_exception_interval  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hours_cache             ENABLE ROW LEVEL SECURITY;
ALTER TABLE aed_photo               ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_member            ENABLE ROW LEVEL SECURITY;
ALTER TABLE otp_challenge           ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_authorization    ENABLE ROW LEVEL SECURITY;
ALTER TABLE report                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_moderation_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE aed_override            ENABLE ROW LEVEL SECURITY;
ALTER TABLE osm_aed                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_flag              ENABLE ROW LEVEL SECURITY;
ALTER TABLE aed_change              ENABLE ROW LEVEL SECURITY;
ALTER TABLE population_cell         ENABLE ROW LEVEL SECURITY;
ALTER TABLE coverage_layer          ENABLE ROW LEVEL SECURITY;
ALTER TABLE coverage_region         ENABLE ROW LEVEL SECURITY;
ALTER TABLE coverage_hour           ENABLE ROW LEVEL SECURITY;
ALTER TABLE relocation_rank         ENABLE ROW LEVEL SECURITY;
ALTER TABLE bo_project              ENABLE ROW LEVEL SECURITY;
ALTER TABLE offline_region          ENABLE ROW LEVEL SECURITY;
ALTER TABLE offline_asset           ENABLE ROW LEVEL SECURITY;
ALTER TABLE offline_release         ENABLE ROW LEVEL SECURITY;

-- Supabase grants new objects to anon/authenticated by default; start from nothing.
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated;

-- Public, read-only data. aed_override is not here: its effect is exposed through aed_public.
GRANT SELECT ON
    data_source, service_area, district, public_holiday, building, address,
    aed, aed_hours, aed_day_state, aed_schedule, aed_hours_exception, aed_exception_interval,
    osm_aed, population_cell, coverage_layer, coverage_region, coverage_hour, relocation_rank, bo_project,
    offline_region, offline_asset, offline_release, aed_public
TO anon, authenticated;
-- Photos: only the EXIF-free copy, never the original file name.
GRANT SELECT (id, aed_id, public_file_name, width, height) ON aed_photo TO anon, authenticated;

CREATE POLICY public_read ON data_source            FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON service_area           FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON district               FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON public_holiday         FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON building               FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON address                FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON aed                    FOR SELECT TO anon, authenticated USING (removed_at IS NULL);
CREATE POLICY public_read ON aed_hours              FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON aed_day_state          FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON aed_schedule           FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON aed_hours_exception    FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON aed_exception_interval FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON osm_aed                FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON population_cell        FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON coverage_layer         FOR SELECT TO anon, authenticated
    USING (status = 'ready' AND retired_at IS NULL);
CREATE POLICY public_read ON coverage_region        FOR SELECT TO anon, authenticated
    USING (EXISTS (SELECT 1 FROM coverage_layer l WHERE l.id = layer_id));
CREATE POLICY public_read ON coverage_hour          FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON relocation_rank        FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON bo_project             FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON offline_region         FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY public_read ON offline_release        FOR SELECT TO anon, authenticated USING (published_at IS NOT NULL);
CREATE POLICY public_read ON offline_asset          FOR SELECT TO anon, authenticated
    USING (EXISTS (SELECT 1 FROM offline_release r WHERE offline_asset.id IN (r.basemap_asset_id, r.aed_asset_id)));
CREATE POLICY public_read ON aed_photo              FOR SELECT TO anon, authenticated USING (public_file_name IS NOT NULL);
-- No policies (service_role only): job, refresh_run, source_snapshot, dataset_version, hours_cache,
-- staff_member, otp_challenge, report_authorization, report, report_moderation_event,
-- aed_override, audit_flag, aed_change.

GRANT EXECUTE ON FUNCTION
    fmt_street(text, text),
    floor_label(smallint),
    dist_m(double precision, double precision, double precision, double precision),
    current_dataset_version(),
    is_inside_warsaw(double precision, double precision),
    aed_effective_state(uuid),
    aed_day(bigint, date),
    aed_availability(uuid, timestamptz, timestamptz),
    aed_is_open(uuid, timestamptz),
    aeds_nearby(double precision, double precision, integer, integer, uuid[])
TO anon, authenticated;
-- submit_report, moderate_report, revoke_override and is_staff stay service_role only.

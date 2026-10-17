-- AED Warszawa: database schema (plain PostgreSQL 14+, no extensions needed).
-- Coordinates are WGS84 lon/lat in double precision. For heavy spatial work see db/postgis_optional.sql.
--
-- Conventions
--   floor     0 = ground floor (parter), 1 = first floor above ground ("I piętro"), -1 = basement, NULL = unknown
--   day       0 = Monday ... 6 = Sunday; times are minutes since midnight (0..1440, 1440 = 24:00)
--   Intervals that cross midnight are stored as two rows (end of day D, start of day D+1).

BEGIN;

CREATE TYPE hours_status  AS ENUM ('24/7', 'scheduled', 'unknown');
CREATE TYPE floor_source  AS ENUM ('text', 'osm', 'manual');
CREATE TYPE match_status  AS ENUM ('matched', 'far', 'no_match');
CREATE TYPE flag_severity AS ENUM ('info', 'warning', 'error');
CREATE TYPE change_type   AS ENUM ('added', 'removed', 'changed');

-- ---------------------------------------------------------------- reference data

CREATE TABLE district (
    id            smallserial PRIMARY KEY,
    name          text NOT NULL UNIQUE,             -- 'Mokotów', 'Praga-Północ' ... (18 districts)
    osm_relation  bigint,
    boundary      jsonb                             -- GeoJSON MultiPolygon for the map layer
);

-- Only buildings that an AED was matched to (not all 184k from the city layer).
CREATE TABLE building (
    id            text PRIMARY KEY,                 -- ID_BUDYNKU from the city GeoServer layer `budynki`
    floors_above  smallint CHECK (floors_above BETWEEN 0 AND 80),
    floors_below  smallint CHECK (floors_below BETWEEN 0 AND 20),
    kind          char(1),                          -- RODZAJ: m residential, i other, t transport, h trade, b office, k education/culture/sport, s health, ...
    footprint     jsonb                             -- GeoJSON geometry, optional
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
    official_lon    double precision,               -- city address point (punkty_adresowe), more reliable than the AED coordinate
    official_lat    double precision,
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

-- ---------------------------------------------------------------- AED

CREATE TABLE aed (
    id                   integer PRIMARY KEY,       -- defibrillator_id in the SCB API
    object_name          text NOT NULL,             -- location_object_name: 'Urząd Dzielnicy Mokotów m.st. Warszawy'
    address_id           bigint NOT NULL REFERENCES address,
    lon                  double precision NOT NULL CHECK (lon BETWEEN 20.7 AND 21.4),
    lat                  double precision NOT NULL CHECK (lat BETWEEN 52.0 AND 52.5),
    -- where exactly
    in_building          boolean NOT NULL,          -- device_location: inside (true) / outside (false) the building
    in_footprint         boolean,                   -- cross-check: the point lies inside a building footprint (NULL = not computed)
    floor                smallint CHECK (floor BETWEEN -5 AND 60),
    floor_source         floor_source,
    location_description text,                      -- 'Przy wejściu głównym, po lewej stronie' (how to find it; shown to the user)
    building_id          text REFERENCES building,
    -- device
    public_access        boolean NOT NULL,          -- device_public_access = 'Publiczny'
    availability_raw     text,                      -- device_availability as given: 'Tak' | 'Nie' | 'Ograniczona' | free text
    manufacturer         text,
    has_specifications   text,                      -- device_specifications: 'Tak' | 'Nie' | 'Brak informacji'
    -- lifecycle (maintained by the refresh job)
    first_seen_at        timestamptz NOT NULL DEFAULT now(),
    last_seen_at         timestamptz NOT NULL DEFAULT now(),
    removed_at           timestamptz,
    source_hash          text,                      -- hash of the raw API record, to detect changes cheaply
    CHECK ((floor IS NULL) = (floor_source IS NULL))
);
CREATE INDEX aed_address_idx ON aed (address_id);
CREATE INDEX aed_lonlat_idx  ON aed (lat, lon);
CREATE INDEX aed_active_idx  ON aed (id) WHERE removed_at IS NULL;

-- Opening hours: raw text + how it was understood.
CREATE TABLE aed_hours (
    aed_id        integer PRIMARY KEY REFERENCES aed ON DELETE CASCADE,
    status        hours_status NOT NULL,
    raw_text      text,                             -- device_access_description (NULL for most 24/7 devices)
    osm_hours     text,                             -- normalized, e.g. 'Mo-Fr 08:00-16:00; Sa 10:00-14:00'
    parse_source  text NOT NULL,                    -- availability_field | regex | llm:<model> | no_text | unparsed | llm_error
    assumed       text[] NOT NULL DEFAULT '{}',     -- weekdays_assumed, metro_hours_assumed
    note          text,                             -- LLM remarks, e.g. holiday exceptions
    parsed_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE aed_schedule (
    aed_id     integer NOT NULL REFERENCES aed ON DELETE CASCADE,
    dow        smallint NOT NULL CHECK (dow BETWEEN 0 AND 6),
    start_min  smallint NOT NULL CHECK (start_min BETWEEN 0 AND 1439),
    end_min    smallint NOT NULL CHECK (end_min BETWEEN 1 AND 1440),
    PRIMARY KEY (aed_id, dow, start_min),
    CHECK (end_min > start_min)
);

-- Cache of LLM answers, keyed by the exact hours string (mirrors data/cache/hours_cache.json).
CREATE TABLE hours_cache (
    raw_text    text PRIMARY KEY,
    status      hours_status NOT NULL,
    schedule    jsonb NOT NULL,
    source      text NOT NULL,
    model       text,
    note        text,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE aed_photo (
    id               serial PRIMARY KEY,
    aed_id           integer NOT NULL REFERENCES aed ON DELETE CASCADE,
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

-- ---------------------------------------------------------------- OpenStreetMap layer

CREATE TABLE osm_aed (
    osm_id         bigint NOT NULL,
    osm_type       text NOT NULL CHECK (osm_type IN ('node', 'way')),
    lon            double precision NOT NULL,
    lat            double precision NOT NULL,
    level          smallint,
    opening_hours  text,
    access         text,
    indoor         boolean,
    operator       text,
    tags           jsonb NOT NULL DEFAULT '{}',
    matched_aed_id integer REFERENCES aed ON DELETE SET NULL,  -- city AED within ~50 m, if any
    match_dist_m   real,
    fetched_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (osm_type, osm_id)
);

-- ---------------------------------------------------------------- audit and refresh history

CREATE TABLE audit_flag (
    id          bigserial PRIMARY KEY,
    aed_id      integer NOT NULL REFERENCES aed ON DELETE CASCADE,
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

CREATE TABLE refresh_run (
    id           bigserial PRIMARY KEY,
    started_at   timestamptz NOT NULL DEFAULT now(),
    finished_at  timestamptz,
    status       text NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'ok', 'failed')),
    total        integer,
    added        integer,
    removed      integer,
    changed      integer,
    llm_calls    integer NOT NULL DEFAULT 0,
    error        text
);

CREATE TABLE aed_change (
    run_id   bigint NOT NULL REFERENCES refresh_run ON DELETE CASCADE,
    aed_id   integer NOT NULL,                      -- no FK: removed devices stay in the history
    kind     change_type NOT NULL,
    before   jsonb,
    after    jsonb,
    PRIMARY KEY (run_id, aed_id)
);

-- ---------------------------------------------------------------- analysis results

CREATE TABLE population_cell (
    code        text PRIMARY KEY,                   -- GUS grid code, 1 km cell
    lon         double precision NOT NULL,          -- cell centre
    lat         double precision NOT NULL,
    residents   integer NOT NULL,
    res_0_14    integer,
    res_15_64   integer,
    res_65_plus integer
);

CREATE TABLE coverage_hour (
    basis        text NOT NULL CHECK (basis IN ('address_points', 'population_cells')),
    include_osm  boolean NOT NULL DEFAULT false,
    radius_m     smallint NOT NULL,
    dow          smallint NOT NULL CHECK (dow BETWEEN 0 AND 6),
    hour         smallint NOT NULL CHECK (hour BETWEEN 0 AND 23),
    available    integer NOT NULL,                  -- AEDs open at that hour (unknown ones excluded)
    covered      real NOT NULL CHECK (covered BETWEEN 0 AND 1),
    computed_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (basis, include_osm, radius_m, dow, hour)
);

CREATE TABLE relocation_rank (
    radius_m       smallint NOT NULL,
    rank           smallint NOT NULL,
    aed_id         integer NOT NULL REFERENCES aed ON DELETE CASCADE,
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

-- Is the AED open at a moment in time? TRUE / FALSE, or NULL when its hours are unknown.
CREATE FUNCTION aed_is_open(p_aed_id integer, p_at timestamptz DEFAULT now()) RETURNS boolean
LANGUAGE sql STABLE AS $$
    WITH t AS (
        SELECT (extract(isodow FROM p_at AT TIME ZONE 'Europe/Warsaw')::int - 1) AS dow,
               (extract(hour FROM p_at AT TIME ZONE 'Europe/Warsaw')::int * 60
                + extract(minute FROM p_at AT TIME ZONE 'Europe/Warsaw')::int) AS minute
    )
    SELECT CASE h.status
        WHEN '24/7' THEN true
        WHEN 'unknown' THEN NULL
        ELSE EXISTS (SELECT 1 FROM aed_schedule s, t
                     WHERE s.aed_id = p_aed_id AND s.dow = t.dow AND t.minute >= s.start_min AND t.minute < s.end_min)
    END
    FROM aed_hours h WHERE h.aed_id = p_aed_id
$$;

-- ---------------------------------------------------------------- what the app reads

-- nav_lon/nav_lat: the official address point when we have one, else the AED coordinate.
-- The links open the place on a map or start walking navigation to it.
CREATE VIEW aed_public AS
SELECT
    a.id,
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
    a.location_description,
    a.public_access,
    h.status                                               AS hours_status,
    h.osm_hours,
    h.raw_text                                             AS hours_raw,
    aed_is_open(a.id)                                      AS open_now,
    b.floors_above                                         AS building_floors,
    coalesce(ad.official_lon, a.lon)                       AS nav_lon,
    coalesce(ad.official_lat, a.lat)                       AS nav_lat,
    'https://www.google.com/maps/search/?api=1&query='
        || coalesce(ad.official_lat, a.lat) || ',' || coalesce(ad.official_lon, a.lon)             AS google_maps_url,
    'https://www.google.com/maps/dir/?api=1&travelmode=walking&destination='
        || coalesce(ad.official_lat, a.lat) || ',' || coalesce(ad.official_lon, a.lon)             AS google_directions_url,
    'https://www.openstreetmap.org/?mlat=' || coalesce(ad.official_lat, a.lat)
        || '&mlon=' || coalesce(ad.official_lon, a.lon)
        || '#map=19/' || coalesce(ad.official_lat, a.lat) || '/' || coalesce(ad.official_lon, a.lon) AS osm_url,
    'https://maps.apple.com/?ll=' || coalesce(ad.official_lat, a.lat) || ',' || coalesce(ad.official_lon, a.lon) AS apple_maps_url,
    'geo:' || coalesce(ad.official_lat, a.lat) || ',' || coalesce(ad.official_lon, a.lon) || '?z=19' AS geo_uri,
    EXISTS (SELECT 1 FROM audit_flag f WHERE f.aed_id = a.id AND f.resolved_at IS NULL AND f.severity <> 'info') AS has_open_flags
FROM aed a
JOIN address ad       ON ad.id = a.address_id
LEFT JOIN district d  ON d.id = ad.district_id
LEFT JOIN aed_hours h ON h.aed_id = a.id
LEFT JOIN building b  ON b.id = a.building_id
WHERE a.removed_at IS NULL;

COMMIT;

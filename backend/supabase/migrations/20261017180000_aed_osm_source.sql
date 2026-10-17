-- Where an AED and its hours come from. `source` separates the city register from devices only OpenStreetMap
-- knows (public access, more than 50 m from any city AED); `hours_source` says which dataset the hours were read from:
-- city, osm, or city_osm when OpenStreetMap repeats the city's days and fills the days the city leaves out.
BEGIN;
SET LOCAL search_path = public, extensions;

ALTER TABLE aeds
    ADD COLUMN source text NOT NULL DEFAULT 'city' CHECK (source IN ('city', 'osm')),
    ADD COLUMN hours_source text CHECK (hours_source IN ('city', 'osm', 'city_osm'));

CREATE OR REPLACE VIEW aed_public WITH (security_invoker = true) AS
SELECT id, source_id, lon, lat, object_name, full_address, access_instructions,
       public_access, operational_status, photo_path, district, source FROM aeds WHERE active;
COMMIT;

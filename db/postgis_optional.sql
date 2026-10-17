-- OPTIONAL, NOT TESTED (no PostGIS was available when the schema was written).
-- Only needed for polygon work in SQL (districts, buildings). The app does not require it.
CREATE EXTENSION IF NOT EXISTS postgis;

ALTER TABLE aed ADD COLUMN geog geography(Point, 4326)
    GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography) STORED;
CREATE INDEX aed_geog_idx ON aed USING gist (geog);

-- AEDs within 400 m of a point:  SELECT id FROM aed WHERE ST_DWithin(geog, ST_MakePoint(21.0151, 52.2478)::geography, 400);
-- District of every address once district.boundary is loaded as a geometry column.

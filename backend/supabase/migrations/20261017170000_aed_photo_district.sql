-- Photo and district for the AED card and list. The photo is a bucket-relative name of the
-- EXIF-free public copy (pipeline/photos.py); originals stay private because their EXIF has GPS.
BEGIN;
SET LOCAL search_path = public, extensions;

ALTER TABLE aeds
    ADD COLUMN photo_path text CHECK (photo_path IS NULL OR photo_path ~ '^[A-Za-z0-9_-]+\.webp$'),
    ADD COLUMN district text;

-- Same columns, appended last: CREATE OR REPLACE VIEW cannot reorder existing ones.
CREATE OR REPLACE VIEW aed_public WITH (security_invoker = true) AS
SELECT id, source_id, lon, lat, object_name, full_address, access_instructions,
       public_access, operational_status, photo_path, district FROM aeds WHERE active;

-- Public-read bucket for the photos. Skipped where Supabase Storage is not installed (plain PostGIS tests).
DO $$ BEGIN
    IF to_regclass('storage.buckets') IS NOT NULL THEN
        INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
        VALUES ('aed-photos', 'aed-photos', true, 524288, ARRAY['image/webp'])
        ON CONFLICT (id) DO NOTHING;
    END IF;
END $$;
COMMIT;

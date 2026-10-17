-- Spam is made cheap to ignore rather than blocked outright: likely-bot reports are flagged
-- (never rejected) and moderators review pending reports grouped per AED and category.
-- Also stops trusting x-forwarded-for as the client identity for the per-client rate limit.
BEGIN;
SET LOCAL search_path = public, extensions;

-- Milliseconds the report form was open before submission, sent by the app.
ALTER TABLE reports ADD COLUMN form_ms integer CHECK (form_ms >= 0);
-- Set by the trigger: 'fast' (no or implausibly short form time), 'link' (URL in the text).
-- Flagged reports stay pending but sink to the bottom of report_queue.
ALTER TABLE reports ADD COLUMN flags text[] NOT NULL DEFAULT '{}';

GRANT INSERT (form_ms) ON reports TO anon, authenticated;

-- PostgREST passes request headers as JSON. Only cf-connecting-ip identifies the client: the
-- Cloudflare edge in front of Supabase overwrites it, while x-forwarded-for keeps whatever the
-- client sent and would let it pick a fresh "IP" per request. Without the header (local stack,
-- dashboard, scripts, tests) only the AED limit applies, and reports outside PostgREST get no flags.
CREATE OR REPLACE FUNCTION report_rate_limit() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
    v_ip text := nullif(btrim(v_headers->>'cf-connecting-ip'), '');
BEGIN
    NEW.reporter_id := auth.uid();
    NEW.client_hash := CASE WHEN v_ip IS NOT NULL THEN encode(sha256(convert_to(v_ip, 'UTF8')), 'hex') END;
    NEW.flags := '{}';
    IF v_headers IS NOT NULL THEN
        IF NEW.form_ms IS NULL OR NEW.form_ms < 3000 THEN NEW.flags := NEW.flags || 'fast'::text; END IF;
        IF NEW.description ~* '(https?://|www\.)' THEN NEW.flags := NEW.flags || 'link'::text; END IF;
    END IF;
    IF NEW.client_hash IS NOT NULL AND (
        SELECT count(*) FROM public.reports
        WHERE client_hash = NEW.client_hash AND created_at > now() - interval '1 hour') >= 5 THEN
        RAISE EXCEPTION 'rate_limited' USING ERRCODE = 'PT429', HINT = 'Too many reports from this client';
    END IF;
    IF (SELECT count(*) FROM public.reports
        WHERE aed_id = NEW.aed_id AND created_at > now() - interval '1 hour') >= 20 THEN
        RAISE EXCEPTION 'rate_limited' USING ERRCODE = 'PT429', HINT = 'Too many reports for this AED';
    END IF;
    RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION report_rate_limit() FROM PUBLIC, anon, authenticated;

-- Moderation queue: one row per AED and category with pending reports. `clients` counts distinct
-- unflagged clients, so many reports from one source or from bots still rank as a weak signal.
CREATE VIEW report_queue WITH (security_invoker = true) AS
SELECT r.aed_id, a.object_name, a.full_address, r.category,
       count(*) AS reports,
       count(*) FILTER (WHERE r.flags <> '{}') AS flagged,
       count(DISTINCT r.client_hash) FILTER (WHERE r.flags = '{}') AS clients,
       min(r.created_at) AS first_at,
       max(r.created_at) AS last_at,
       (array_agg(r.description ORDER BY r.flags <> '{}', r.created_at DESC))[1:3] AS sample_descriptions
FROM public.reports r JOIN public.aeds a ON a.id = r.aed_id
WHERE r.status = 'pending'
GROUP BY r.aed_id, a.object_name, a.full_address, r.category
ORDER BY clients DESC, last_at DESC;
REVOKE ALL ON report_queue FROM PUBLIC, anon, authenticated;
GRANT SELECT ON report_queue TO service_role;

-- Accept or reject a whole queue row at once. Pass its last_at so reports that arrived after
-- the moderator looked stay pending. Returns the number of reports changed.
CREATE FUNCTION moderate_report_group(p_aed_id uuid, p_category text, p_status text, p_until timestamptz)
RETURNS integer LANGUAGE sql SET search_path = '' AS $$
    WITH changed AS (
        UPDATE public.reports SET status = p_status
        WHERE aed_id = p_aed_id AND category = p_category AND status = 'pending' AND created_at <= p_until
        RETURNING 1)
    SELECT count(*)::integer FROM changed
$$;
REVOKE ALL ON FUNCTION moderate_report_group(uuid, text, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION moderate_report_group(uuid, text, text, timestamptz) TO service_role;
COMMIT;

-- Reports no longer need phone verification: anyone can submit one for an active AED.
-- Abuse is limited by a per-client and a per-AED rate limit instead of an SMS code.
-- Clients insert with a client-generated `id` (the idempotency key) and `return=minimal`;
-- a retried insert with the same id fails with a unique violation and is not a new report.
BEGIN;
SET LOCAL search_path = public, extensions;

DROP POLICY submit_own_report ON reports;
DROP FUNCTION phone_verified();
REVOKE INSERT ON reports FROM authenticated;

-- SHA-256 of the client IP, kept only for rate limiting. Never exposed to public roles.
ALTER TABLE reports ADD COLUMN client_hash text;
CREATE INDEX reports_client_recent_idx ON reports (client_hash, created_at) WHERE client_hash IS NOT NULL;
CREATE INDEX reports_aed_recent_idx ON reports (aed_id, created_at);

GRANT INSERT (id, aed_id, category, description) ON reports TO anon, authenticated;
CREATE POLICY submit_report ON reports FOR INSERT TO anon, authenticated
    WITH CHECK (EXISTS (SELECT 1 FROM public.aeds WHERE id = aed_id AND active));

-- PostgREST passes request headers as JSON; cf-connecting-ip is set by the Supabase edge.
-- Outside PostgREST (dashboard, scripts, tests) there is no client and only the AED limit applies.
CREATE FUNCTION report_rate_limit() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
    v_ip text := coalesce(v_headers->>'cf-connecting-ip',
                          nullif(btrim(split_part(v_headers->>'x-forwarded-for', ',', 1)), ''));
BEGIN
    NEW.reporter_id := auth.uid();
    NEW.client_hash := CASE WHEN v_ip IS NOT NULL THEN encode(sha256(convert_to(v_ip, 'UTF8')), 'hex') END;
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
CREATE TRIGGER reports_rate_limit BEFORE INSERT ON reports FOR EACH ROW EXECUTE FUNCTION report_rate_limit();
COMMIT;

-- C47 ISOLATED PROPOSAL / not applied. Requires verified 019-024.
-- Database-authoritative Daily/Weekly scope for claims, leases and exhausted cleanup.
BEGIN;
DO $$
BEGIN
  IF to_regclass('public.delivery_ledger') IS NULL
     OR to_regprocedure('public.claim_delivery_jobs(timestamptz,integer)') IS NULL
     OR to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.claim_delivery_jobs(text,timestamptz,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'C47 025 requires exact reviewed 024 schema and no scoped-claim overload';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_depend d
    WHERE d.refobjid=to_regprocedure('public.claim_delivery_jobs(timestamptz,integer)')
      AND d.deptype='n') THEN
    RAISE EXCEPTION 'Unscoped claim RPC has dependents; investigate before replacement';
  END IF;
END $$;

CREATE FUNCTION public.claim_delivery_jobs(
  p_kind text,
  p_now timestamptz DEFAULT now(),
  p_limit integer DEFAULT 100
)
RETURNS TABLE(
  job_id uuid,
  user_id uuid,
  kind text,
  delivery_key text,
  scheduled_for timestamptz,
  claim_token uuid
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
  IF p_kind IS NULL OR p_kind NOT IN ('daily_reminder','weekly_newsletter') THEN
    RAISE EXCEPTION 'Unsupported delivery kind' USING ERRCODE='22023';
  END IF;
  IF p_now IS NULL THEN
    RAISE EXCEPTION 'A claim timestamp is required' USING ERRCODE='22023';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 1000 THEN
    RAISE EXCEPTION 'p_limit must be between 1 and 1000' USING ERRCODE='22023';
  END IF;

  UPDATE public.delivery_ledger dl
  SET state='failed', failed_at=p_now, claim_token=NULL, claim_expires_at=NULL,
      next_attempt_at=NULL, error_code='retry_exhausted', updated_at=now()
  WHERE dl.kind=p_kind
    AND dl.state='claimed'
    AND dl.claim_expires_at IS NOT NULL
    AND dl.claim_expires_at <= p_now
    AND dl.attempt_count >= 5;

  RETURN QUERY
  WITH picked AS (
    SELECT dl.id
    FROM public.delivery_ledger dl
    WHERE dl.kind=p_kind AND (
      (dl.state='queued'
        AND coalesce(dl.next_attempt_at,dl.scheduled_for)<=p_now
        AND dl.attempt_count<5)
      OR (dl.state='claimed'
        AND dl.claim_expires_at IS NOT NULL
        AND dl.claim_expires_at<=p_now
        AND dl.attempt_count<5)
    )
    ORDER BY coalesce(dl.next_attempt_at,dl.scheduled_for),dl.created_at,dl.id
    FOR UPDATE SKIP LOCKED
    LIMIT p_limit
  ), claimed AS (
    UPDATE public.delivery_ledger dl
    SET state='claimed', claim_token=gen_random_uuid(), claimed_at=p_now,
        claim_expires_at=p_now+interval '5 minutes',
        attempt_count=dl.attempt_count+1, last_attempt_at=p_now,
        next_attempt_at=NULL, error_code=NULL, updated_at=now()
    FROM picked
    WHERE dl.id=picked.id AND dl.kind=p_kind
    RETURNING dl.id,dl.user_id,dl.kind,dl.delivery_key,dl.scheduled_for,dl.claim_token
  )
  SELECT claimed.id,claimed.user_id,claimed.kind,claimed.delivery_key,
         claimed.scheduled_for,claimed.claim_token
  FROM claimed;
END $$;

REVOKE ALL ON FUNCTION public.claim_delivery_jobs(text,timestamptz,integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_delivery_jobs(text,timestamptz,integer)
  TO service_role;
-- Not a revocation-only placeholder: remove the unsafe callable overload.
REVOKE ALL ON FUNCTION public.claim_delivery_jobs(timestamptz,integer)
  FROM PUBLIC, anon, authenticated, service_role;
DROP FUNCTION public.claim_delivery_jobs(timestamptz,integer);
COMMIT;

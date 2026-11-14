-- REVIEW-ONLY PROPOSAL. Authorized Developer must allocate final migration number with CLI.
-- Depends on verified DeedLight migration 024 and provider_result_id ledger column.
-- NEVER execute against Production without separately approved exact-schema preflight.
begin;

do $$ begin
  if to_regclass('public.delivery_ledger') is null
     or to_regprocedure('public.mark_delivery_sent(uuid,uuid,text)') is null
     or to_regprocedure('public.claim_delivery_jobs(text,timestamptz,integer)') is null
     or to_regprocedure('public.claim_delivery_jobs(timestamptz,integer)') is not null
     or to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') is null
     or to_regclass('public.delivery_provider_submissions') is not null
     or to_regprocedure('public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)') is not null then
    raise exception 'Webhook migration requires reviewed 024 state and unapplied lifecycle schema.';
  end if;
end $$;

create table public.delivery_provider_submissions (
  job_id uuid primary key references public.delivery_ledger(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  provider_email_id text not null unique check (char_length(provider_email_id) between 1 and 255),
  recipient_fingerprint text not null check (recipient_fingerprint ~ '^[0-9a-f]{64}$'),
  lifecycle_state text not null default 'accepted'
    check (lifecycle_state in ('accepted','sent','delayed','failed','delivered','suppressed','bounced','complained')),
  last_event_at timestamptz,
  last_event_type text,
  created_at timestamptz not null default clock_timestamp()
);

create table public.delivery_provider_events (
  svix_event_id text primary key check (char_length(svix_event_id) between 10 and 200),
  job_id uuid not null references public.delivery_provider_submissions(job_id) on delete cascade,
  provider_email_id text not null,
  recipient_fingerprint text not null check (recipient_fingerprint ~ '^[0-9a-f]{64}$'),
  event_type text not null check (event_type in (
    'email.sent','email.delivered','email.delivery_delayed','email.failed',
    'email.bounced','email.complained','email.suppressed'
  )),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  event_at timestamptz not null,
  suppression_reason text check (suppression_reason in ('permanent_bounce','spam_complaint')),
  received_at timestamptz not null default clock_timestamp()
);
create index delivery_provider_events_job_idx on public.delivery_provider_events(job_id, event_at desc);

create table public.delivery_recipient_suppressions (
  recipient_fingerprint text primary key check (recipient_fingerprint ~ '^[0-9a-f]{64}$'),
  first_job_id uuid references public.delivery_ledger(id) on delete set null,
  reason text not null check (reason in ('permanent_bounce','spam_complaint')),
  source_event_id text not null,
  created_at timestamptz not null default clock_timestamp()
);

alter table public.delivery_provider_submissions enable row level security;
alter table public.delivery_provider_events enable row level security;
alter table public.delivery_recipient_suppressions enable row level security;
revoke all on table public.delivery_provider_submissions from public,anon,authenticated,service_role;
revoke all on table public.delivery_provider_events from public,anon,authenticated,service_role;
revoke all on table public.delivery_recipient_suppressions from public,anon,authenticated,service_role;

-- Same transaction as old claim-token/lease validated sent transition.
-- service_role may invoke only this recipient-bound wrapper, never the old RPC.
create function public.mark_delivery_sent_with_recipient(
  p_job_id uuid,
  p_claim_token uuid,
  p_provider_email_id text,
  p_recipient_fingerprint text
) returns boolean
language plpgsql security definer set search_path = pg_catalog, pg_temp
as $$
declare v_user uuid;
begin
  if p_job_id is null or p_claim_token is null
     or p_provider_email_id is null or char_length(p_provider_email_id) not between 1 and 255
     or nullif(btrim(p_provider_email_id),'') is null
     or p_recipient_fingerprint is null or p_recipient_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid provider submission arguments.' using errcode='22023';
  end if;
  select user_id into v_user from public.delivery_ledger where id=p_job_id for update;
  if not found then raise exception 'Unknown job.' using errcode='42501'; end if;
  if public.mark_delivery_sent(p_job_id,p_claim_token,p_provider_email_id) is not true then
    raise exception 'Delivery mark-sent authorization failed.' using errcode='42501';
  end if;
  insert into public.delivery_provider_submissions
    (job_id,user_id,provider_email_id,recipient_fingerprint)
  values (p_job_id,v_user,p_provider_email_id,p_recipient_fingerprint);
  return true;
end $$;
revoke all on function public.mark_delivery_sent_with_recipient(uuid,uuid,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.mark_delivery_sent_with_recipient(uuid,uuid,text,text) to service_role;
revoke all on function public.mark_delivery_sent(uuid,uuid,text)
  from public,anon,authenticated,service_role;

-- Atomic message association, event-ID deduplication and safety state update.
-- Caller MUST have independently verified the Svix signature over raw body.
create function public.record_resend_webhook_event(
  p_event_id text,
  p_provider_email_id text,
  p_recipient_fingerprint text,
  p_event_type text,
  p_event_at timestamptz,
  p_payload_sha256 text,
  p_suppression_reason text default null
) returns text
language plpgsql security definer set search_path = pg_catalog, pg_temp
as $$
declare
  v_sub public.delivery_provider_submissions%rowtype;
  v_event public.delivery_provider_events%rowtype;
  v_inserted text;
  v_next_state text;
begin
  if p_event_id is null or p_event_id !~ '^msg_[A-Za-z0-9_-]{6,180}$'
    or p_provider_email_id is null or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_fingerprint is null or p_recipient_fingerprint !~ '^[0-9a-f]{64}$'
    or p_payload_sha256 is null or p_payload_sha256 !~ '^[0-9a-f]{64}$'
    or p_event_at is null
    or p_event_type is null or p_event_type not in (
      'email.sent','email.delivered','email.delivery_delayed','email.failed',
      'email.bounced','email.complained','email.suppressed')
    or (p_suppression_reason is not null and (
       (p_suppression_reason='permanent_bounce' and p_event_type<>'email.bounced')
       or (p_suppression_reason='spam_complaint' and p_event_type<>'email.complained')
       or p_suppression_reason not in ('permanent_bounce','spam_complaint')))
    or (p_event_type='email.complained' and p_suppression_reason is distinct from 'spam_complaint')
  then raise exception 'Invalid verified webhook event.' using errcode='22023'; end if;

  -- Locks against concurrent same-submission events and deletion.
  select * into v_sub from public.delivery_provider_submissions
  where provider_email_id=p_provider_email_id for update;
  if not found then raise exception 'Unknown provider submission.' using errcode='23503'; end if;
  if v_sub.recipient_fingerprint is distinct from p_recipient_fingerprint then
    raise exception 'Provider recipient association mismatch.' using errcode='42501';
  end if;

  insert into public.delivery_provider_events
    (svix_event_id,job_id,provider_email_id,recipient_fingerprint,event_type,
     event_at,payload_sha256,suppression_reason)
  values (p_event_id,v_sub.job_id,p_provider_email_id,p_recipient_fingerprint,p_event_type,
          p_event_at,p_payload_sha256,p_suppression_reason)
  on conflict (svix_event_id) do nothing
  returning svix_event_id into v_inserted;
  if v_inserted is null then
    select * into v_event from public.delivery_provider_events where svix_event_id=p_event_id;
    if not found
       or v_event.job_id is distinct from v_sub.job_id
       or v_event.provider_email_id is distinct from p_provider_email_id
       or v_event.recipient_fingerprint is distinct from p_recipient_fingerprint
       or v_event.event_type is distinct from p_event_type
       or v_event.payload_sha256 is distinct from p_payload_sha256
       or v_event.event_at is distinct from p_event_at
       or v_event.suppression_reason is distinct from p_suppression_reason then
      raise exception 'Webhook event ID reused with different content.' using errcode='23505';
    end if;
    return 'duplicate';
  end if;

  -- Permanent safety decisions dominate all subsequent informational events.
  v_next_state := case
    when p_suppression_reason='spam_complaint' then 'complained'
    when p_suppression_reason='permanent_bounce' then 'bounced'
    when p_event_type='email.suppressed' then 'suppressed'
    when p_event_type='email.delivered' then 'delivered'
    when p_event_type='email.failed' then 'failed'
    when p_event_type='email.bounced' then 'delayed' -- temporary/indeterminate bounce
    when p_event_type='email.delivery_delayed' then 'delayed'
    else 'sent' end;
  update public.delivery_provider_submissions set
    lifecycle_state = case
      when lifecycle_state='complained' then 'complained'
      when lifecycle_state='bounced' and v_next_state<>'complained' then 'bounced'
      when lifecycle_state='suppressed' and v_next_state not in ('complained','bounced') then 'suppressed'
      when v_next_state in ('complained','bounced','suppressed') then v_next_state
      when lifecycle_state='delivered' then 'delivered'
      when v_next_state='delivered' then 'delivered'
      when lifecycle_state='failed' and v_next_state in ('sent','delayed') then 'failed'
      when lifecycle_state='delayed' and v_next_state='sent' then 'delayed'
      else v_next_state end,
    last_event_at = greatest(coalesce(last_event_at,p_event_at),p_event_at),
    last_event_type = case when last_event_at is null or p_event_at>=last_event_at
      then p_event_type else last_event_type end
  where job_id=v_sub.job_id;

  if p_suppression_reason is not null then
    insert into public.delivery_recipient_suppressions
      (recipient_fingerprint,first_job_id,reason,source_event_id)
    values (p_recipient_fingerprint,v_sub.job_id,p_suppression_reason,p_event_id)
    on conflict (recipient_fingerprint) do update set
      reason=case when public.delivery_recipient_suppressions.reason='spam_complaint'
        then 'spam_complaint' when excluded.reason='spam_complaint'
        then 'spam_complaint' else 'permanent_bounce' end;
  end if;
  return 'recorded';
end $$;
revoke all on function public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text) to service_role;
commit;

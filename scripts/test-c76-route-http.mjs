import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash, createHmac, randomBytes } from 'node:crypto';
import fs from 'node:fs';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// Execute from the isolated application checkout with Node 24 + npm ci.
const requireApp = createRequire(resolve('package.json'));
const ts = requireApp('typescript');
const postgresDb = 'deedlight_c76_http';
const signer = randomBytes(32);
const signingSecret = `whsec_${signer.toString('base64')}`;
const providerCalls = [];
const rpcCalls = [];

process.env.RESEND_WEBHOOK_SECRET = signingSecret;
process.env.SUPABASE_URL = 'https://c76-synthetic.supabase.co';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'c76-local-synthetic-role';
process.env.DELIVERY_ENABLED = 'false';

function sql(text, vars = {}) {
  const args = [
    '-X', '-At', '-q', '-v', 'ON_ERROR_STOP=1', '-d', postgresDb,
    ...Object.entries(vars).flatMap(([key, value]) => ['-v', `${key}=${String(value)}`]),
  ];
  const p = spawnSync('psql', args, {
    input: text,
    encoding: 'utf8',
    env: { ...process.env, PGHOST: '127.0.0.1', PGPORT: '5432', PGUSER: 'postgres', PGPASSWORD: 'postgres' },
    timeout: 15000,
    maxBuffer: 1024 * 1024,
  });
  if (p.status !== 0) {
    throw Error(`Synthetic PostgreSQL operation failed (exit ${p.status})`);
  }
  return p.stdout.trim().split('\n').filter(Boolean).at(-1) ?? '';
}

function quoted(v) {
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(v)) throw Error('Invalid SQL variable name');
  return `:'${v}'`;
}

async function rpc(name, args) {
  rpcCalls.push(name);
  const operations = {
    deedlight_record_resend_delivery_v2: {
      vars: ['p_event_id', 'p_provider_email_id', 'p_recipient_email', 'p_event_type', 'p_event_at', 'p_payload_sha256', 'p_suppression_reason', 'p_bounce_type'],
      sql: `SELECT public.deedlight_record_resend_delivery_v2(
        :'p_event_id', :'p_provider_email_id', :'p_recipient_email', :'p_event_type',
        :'p_event_at'::timestamptz, :'p_payload_sha256', NULLIF(:'p_suppression_reason', '__NULL__'),
        NULLIF(:'p_bounce_type', '__NULL__'));`,
    },
    deedlight_record_resend_suppression_verified: {
      vars: ['p_event_id', 'p_suppression_id', 'p_recipient_email', 'p_origin', 'p_source_id', 'p_event_type', 'p_event_at', 'p_payload_sha256'],
      sql: `SELECT public.deedlight_record_resend_suppression_verified(
        :'p_event_id', :'p_suppression_id', :'p_recipient_email', :'p_origin',
        NULLIF(:'p_source_id', '__NULL__'), :'p_event_type', :'p_event_at'::timestamptz,
        :'p_payload_sha256');`,
    },
    authorize_delivery_job: {
      vars: ['p_job_id', 'p_claim_token'],
      sql: `SELECT public.authorize_delivery_job(:'p_job_id'::uuid, :'p_claim_token'::uuid)::text;`,
    },
    begin_delivery_transport_identity_bound: {
      vars: ['p_job_id', 'p_claim_token', 'p_expected_email'],
      sql: `SELECT coalesce(public.begin_delivery_transport_identity_bound(
        :'p_job_id'::uuid, :'p_claim_token'::uuid, :'p_expected_email')::text, '__NULL__');`,
    },
    mark_delivery_sent_identity_bound: {
      vars: ['p_job_id', 'p_claim_token', 'p_provider_email_id'],
      sql: `SELECT public.mark_delivery_sent_identity_bound(
        :'p_job_id'::uuid, :'p_claim_token'::uuid, :'p_provider_email_id')::text;`,
    },
    mark_delivery_failed: {
      vars: ['p_job_id', 'p_claim_token', 'p_error_code'],
      sql: `SELECT public.mark_delivery_failed(:'p_job_id'::uuid, :'p_claim_token'::uuid, :'p_error_code')::text;`,
    },
    retry_delivery_job: {
      vars: ['p_job_id', 'p_claim_token', 'p_retry_at', 'p_error_code'],
      sql: `SELECT public.retry_delivery_job(
        :'p_job_id'::uuid, :'p_claim_token'::uuid, :'p_retry_at'::timestamptz, :'p_error_code')::text;`,
    },
  };
  const op = operations[name];
  if (!op) throw Error(`Unexpected synthetic RPC ${name}`);
  const safeVars = Object.fromEntries(op.vars.map((key) => [key, args[key] ?? '__NULL__']));
  try {
    const value = sql(`SET ROLE service_role;\n${op.sql}\nRESET ROLE;`, safeVars);
    return {
      data: value === '__NULL__' ? null : ['t','true'].includes(value) ? true : ['f','false'].includes(value) ? false : value,
      error: null,
    };
  } catch {
    return { data: null, error: { code: 'C75_SYNTHETIC_DB_ERROR' } };
  }
}

function loadTs(filename, overrides = {}) {
  const source = fs.readFileSync(resolve(filename), 'utf8');
  const transformed = ts.transpileModule(source, {
    fileName: filename,
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    reportDiagnostics: true,
  });
  if (transformed.diagnostics?.length) throw Error('TypeScript transpilation diagnostics');
  const module = { exports: {} };
  const dependent = (name) => Object.hasOwn(overrides, name) ? overrides[name] : requireApp(name);
  new Function('module', 'exports', 'require', 'process', transformed.outputText)(
    module, module.exports, dependent, process,
  );
  return module.exports;
}

const verifier = loadTs('lib/delivery/resend-webhook.ts');
const route = loadTs('app/api/webhooks/resend/route.ts', {
  '@supabase/supabase-js': {
    createClient(url, key, opts) {
      assert.equal(url, 'https://c76-synthetic.supabase.co');
      assert.equal(key, 'c76-local-synthetic-role');
      assert.equal(opts.auth.persistSession, false);
      return { rpc };
    },
  },
  '@/lib/delivery/resend-webhook': verifier,
});
const { processClaimedDelivery } = await import(pathToFileURL(resolve('lib/delivery/run-delivery.ts')).href);
const { parseDeliveryRuntimeConfig } = await import(pathToFileURL(resolve('lib/delivery/config.ts')).href);
const { SupabaseDeliveryRuntime } = await import(pathToFileURL(resolve('lib/delivery/supabase-runtime.ts')).href);
const { runScheduledDelivery } = await import(pathToFileURL(resolve('lib/delivery/scheduler.ts')).href);

const databaseGateway = new SupabaseDeliveryRuntime({ rpc });
const reader = createServer(async (incoming, outgoing) => {
  try {
    const pieces = [];
    for await (const piece of incoming) pieces.push(piece);
    const raw = Buffer.concat(pieces);
    const request = new Request('http://127.0.0.1/webhooks/resend', {
      method: 'POST', body: raw, headers: incoming.headers,
    });
    const result = await route.POST(request);
    outgoing.writeHead(result.status, Object.fromEntries(result.headers));
    outgoing.end(Buffer.from(await result.arrayBuffer()));
  } catch {
    outgoing.writeHead(500);
    outgoing.end('Synthetic adapter failed');
  }
});
await new Promise((ok) => reader.listen(0, '127.0.0.1', ok));
const url = `http://127.0.0.1:${reader.address().port}/webhooks/resend`;
const syntheticEmail = 'c76-roundtrip@example.test';
const identity = '70000000-0000-0000-0000-000000000076';
const monday = new Date();
monday.setUTCDate(monday.getUTCDate() - (monday.getUTCDay() + 6) % 7);
const weekStart = monday.toISOString().slice(0, 10);

function signedEvent(eventId, type, extras = {}) {
  const now = Date.now();
  const body = JSON.stringify({
    type,
    created_at: new Date(now).toISOString(),
    data: { email_id: 'provider-c76-roundtrip-001', to: [syntheticEmail], ...extras },
  });
  const timestamp = String(Math.floor(now / 1000));
  const signature = 'v1,' + createHmac('sha256', signer)
    .update(`${eventId}.${timestamp}.${body}`).digest('base64');
  return { body, headers: {
    'content-type': 'application/json',
    'svix-id': eventId,
    'svix-timestamp': timestamp,
    'svix-signature': signature,
  } };
}

function signedAccountEvent(eventId, type, email, sourceId = null) {
  const now = Date.now();
  const body = JSON.stringify({
    type, created_at: new Date(now).toISOString(),
    data: {
      id: 'fe9751fd-9b5f-4aa8-9e04-50abbb6ad241',
      email, origin: 'manual', source_id: sourceId,
      created_at: new Date(now).toISOString(),
    },
  });
  const timestamp = String(Math.floor(now / 1000));
  const signature = 'v1,' + createHmac('sha256', signer)
    .update(`${eventId}.${timestamp}.${body}`).digest('base64');
  return { body, headers: {
    'content-type': 'application/json', 'svix-id': eventId,
    'svix-timestamp': timestamp, 'svix-signature': signature,
  } };
}

function syntheticMember() {
  sql(`
    INSERT INTO auth.users(id,email,email_confirmed_at)
      VALUES (:'identity'::uuid,:'email',now());
    INSERT INTO public.profiles(user_id,is_suspended)
      VALUES (:'identity'::uuid,false);
    INSERT INTO public.daily_reminder_preferences(user_id,daily_enabled,reminder_time,timezone)
      VALUES (:'identity'::uuid,true,'00:00','UTC');
    INSERT INTO public.newsletter_preferences(user_id,weekly_enabled,consented_at)
      VALUES (:'identity'::uuid,true,now());
    INSERT INTO public.weekly_goodness_features(week_start)
      VALUES (:'week_start'::date) ON CONFLICT DO NOTHING;
  `, { identity, email: syntheticEmail, week_start: weekStart });
}
function queue(kind, deliveryKey, scheduledAtSql) {
  const key = kind === 'daily_reminder' ? 'daily:' + scheduledAtSql : 'weekly:' + weekStart;
  // Caller-chosen string is passed as an interpolated psql variable, not SQL.
  const scheduleExpr = kind === 'daily_reminder'
    ? `(:'delivery_key_date'::date + time '00:00') AT TIME ZONE 'UTC'`
    : `now() - interval '1 minute'`;
  sql(`INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
      VALUES (:'identity'::uuid,:'kind',:'key',${scheduleExpr});`, {
    identity, kind, key, delivery_key_date: scheduledAtSql,
  });
  return key;
}
function claim(kind) {
  sql(`SET ROLE service_role;
    SELECT count(*) FROM public.claim_delivery_jobs(:'kind',now(),100);
    RESET ROLE;`, { kind });
}
function job(key) {
  const line = sql(`
    SELECT id::text || '|' || user_id::text || '|' || kind || '|' ||
      delivery_key || '|' || scheduled_for::text || '|' || claim_token::text
    FROM public.delivery_ledger WHERE user_id=:'identity'::uuid AND delivery_key=:'key';`,
    { identity, key });
  const [jobId,userId,kind,deliveryKey,scheduledFor,claimToken] = line.split('|');
  assert(jobId && claimToken, 'Synthetic claimed job unavailable');
  return { jobId,userId,kind,deliveryKey,scheduledFor,claimToken };
}
async function dispatch(jobToSend) {
  const oldCount = providerCalls.length;
  const result = await processClaimedDelivery({
    job: jobToSend,
    gateway: databaseGateway,
    recipientResolver: { async resolve() { return { email: syntheticEmail }; } },
    transport: { async send(delivery) {
      providerCalls.push({ id: delivery.jobId, kind: delivery.kind });
      return { status: 'sent', providerResultId: 'provider-c76-roundtrip-001' };
    } },
  });
  return { result, attempted: providerCalls.length - oldCount };
}
let cases = 0;
try {
  syntheticMember();
  const yesterday = new Date(Date.now()-86400000).toISOString().slice(0,10);
  const today = new Date().toISOString().slice(0,10);
  const first = queue('daily_reminder', '', yesterday);
  claim('daily_reminder');
  const out = await dispatch(job(first));
  assert.deepEqual(out, { result: 'sent', attempted: 1 });
  cases++;
  console.log('Claim -> current consent -> DB final authorization -> one synthetic provider send -> mark-sent: PASS');

  const bounced = signedEvent('msg_c76_roundtrip_bounce001', 'email.bounced', {
    bounce: { type: 'Permanent', subType: 'General' },
  });
  const response = await fetch(url,{method:'POST',headers:bounced.headers,body:bounced.body});
  assert.equal(response.status, 200);
  const payloadHash=createHash('sha256').update(bounced.body).digest('hex');
  assert.equal(sql(`SELECT payload_sha256 FROM public.delivery_provider_events WHERE svix_event_id=:'event_id'`,
    {event_id:'msg_c76_roundtrip_bounce001'}),payloadHash);
  assert.equal(sql(`SELECT reason FROM public.delivery_recipient_suppressions s
    JOIN public.delivery_provider_submissions p USING(recipient_fingerprint)
    WHERE p.provider_email_id='provider-c76-roundtrip-001'`),'permanent_bounce');
  cases++;
  console.log('Signed localhost HTTP webhook -> actual PostgreSQL registry -> durable bounce suppression: PASS');

  const replay = await fetch(url,{method:'POST',headers:bounced.headers,body:bounced.body});
  assert.equal(replay.status,200);
  assert.equal(sql(`SELECT count(*) FROM deedlight_event_private.provider_event_registry
    WHERE event_id='msg_c76_roundtrip_bounce001'`),'1');
  cases++;
  console.log('Signed duplicate webhook HTTP -> one global provider identity: PASS');

  const second = queue('daily_reminder','',today);
  claim('daily_reminder');
  const cancelled = await dispatch(job(second));
  assert.deepEqual(cancelled,{result:'cancelled',attempted:0});
  cases++;
  console.log('Permanent bounce blocks subsequent Daily external send attempt: PASS');

  const weekly = queue('weekly_newsletter','',weekStart);
  claim('weekly_newsletter');
  const weeklyResult=await dispatch(job(weekly));
  assert.deepEqual(weeklyResult,{result:'cancelled',attempted:0});
  cases++;
  console.log('Permanent bounce blocks Weekly external send on same recipient: PASS');

  const disabled = await runScheduledDelivery({DELIVERY_ENABLED:'false'}, {
    cron:'*/5 * * * *',scheduledTime:Date.now(),
  });
  assert.equal(disabled.enabled,false);
  assert.equal(disabled.claimed,0);
  assert.equal(providerCalls.length,1);
  cases++;
  console.log('DELIVERY_ENABLED=false prevents scheduling and synthetic transport: PASS');

  assert.equal(parseDeliveryRuntimeConfig({}).enabled,false);
  assert.throws(()=>parseDeliveryRuntimeConfig({DELIVERY_ENABLED:'true'}));
  cases++;
  console.log('Missing delivery configuration remains fail-closed: PASS');

  // A second signed complaint must not undo the original recipient suppression.
  const complained = signedEvent('msg_c76_roundtrip_complaint001','email.complained');
  const resp2=await fetch(url,{method:'POST',headers:complained.headers,body:complained.body});
  assert.equal(resp2.status,200);
  assert.equal(sql(`SELECT suppression_reason FROM public.delivery_recipient_state s
    JOIN public.delivery_provider_submissions p USING(recipient_fingerprint)
    WHERE p.provider_email_id='provider-c76-roundtrip-001'`),'spam_complaint');
  cases++;
  console.log('Signed complaint escalates bounce to durable spam hold: PASS');

  const add = signedAccountEvent('msg_c76_account_added01','suppression.added',syntheticEmail,'provider-c76-roundtrip-001');
  const addResponse = await fetch(url,{method:'POST',headers:add.headers,body:add.body});
  assert.equal(addResponse.status,200);
  assert.equal(sql(`SELECT count(*) FROM deedlight_event_private.c76_account_suppression_events
    WHERE event_id='msg_c76_account_added01'`),'1');
  assert.equal(sql(`SELECT provider_suppressed::text FROM public.delivery_recipient_state s
    JOIN public.delivery_provider_submissions p USING(recipient_fingerprint)
    WHERE p.provider_email_id='provider-c76-roundtrip-001'`),'true');
  cases++;
  console.log('Signed account suppression.added -> PostgreSQL global registry + durable recipient hold: PASS');

  const remove = signedAccountEvent('msg_c76_account_removed1','suppression.removed',syntheticEmail,'provider-c76-roundtrip-001');
  const removeResponse = await fetch(url,{method:'POST',headers:remove.headers,body:remove.body});
  assert.equal(removeResponse.status,200);
  assert.equal(sql(`SELECT suppression_reason FROM public.delivery_recipient_state s
    JOIN public.delivery_provider_submissions p USING(recipient_fingerprint)
    WHERE p.provider_email_id='provider-c76-roundtrip-001'`),'spam_complaint');
  assert.equal(sql(`SELECT provider_suppressed::text FROM public.delivery_recipient_state s
    JOIN public.delivery_provider_submissions p USING(recipient_fingerprint)
    WHERE p.provider_email_id='provider-c76-roundtrip-001'`),'true');
  cases++;
  console.log('Signed account suppression.removed commits audit only, no release of complaint: PASS');

  const secondEmail='c76-uncertain-http@example.test';
  const secondId='70000000-0000-0000-0000-000000000096';
  sql(`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES (:'uid'::uuid,:'email',now());
    INSERT INTO public.profiles(user_id,is_suspended) VALUES (:'uid'::uuid,false);
    INSERT INTO public.daily_reminder_preferences(user_id,daily_enabled,reminder_time,timezone)
      VALUES (:'uid'::uuid,true,'00:00','UTC');
    INSERT INTO public.newsletter_preferences(user_id,weekly_enabled,consented_at)
      VALUES (:'uid'::uuid,true,now());
    INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
      VALUES (:'uid'::uuid,'daily_reminder','daily:' || (timezone('UTC',now())::date - 1)::text,
        ((timezone('UTC',now())::date - 1) + time '00:00') AT TIME ZONE 'UTC');`,
    {uid:secondId,email:secondEmail});
  claim('daily_reminder');
  const secondJobString=sql(`SELECT id::text || '|' || user_id::text || '|' || kind || '|' ||
    delivery_key || '|' || scheduled_for::text || '|' || claim_token::text
    FROM public.delivery_ledger WHERE user_id=:'uid'::uuid`,{uid:secondId});
  const [secondJobId,secondUserId,secondKind,secondKey,secondScheduled,secondToken]=secondJobString.split('|');
  assert(secondToken && secondKind==='daily_reminder');
  const secondJob={jobId:secondJobId,userId:secondUserId,kind:secondKind,
    deliveryKey:secondKey,scheduledFor:secondScheduled,claimToken:secondToken};
  let secondAttempted=0;
  const secondSend=await processClaimedDelivery({job:secondJob,gateway:databaseGateway,
    recipientResolver:{async resolve(){return {email:secondEmail};}},
    transport:{async send(){secondAttempted++;return {status:'sent',providerResultId:'provider-c76-uncertain-001'};}}});
  assert.equal(secondSend,'sent');
  assert.equal(secondAttempted,1);
  const unknownBounce=signedEvent('msg_c76_undetermined_http01','email.bounced',{
    email_id:'provider-c76-uncertain-001',to:[secondEmail],
    bounce:{type:'Undetermined',subType:'Undetermined',diagnosticCode:[],message:'synthetic'},
  });
  const uncertainResponse=await fetch(url,{method:'POST',headers:unknownBounce.headers,body:unknownBounce.body});
  assert.equal(uncertainResponse.status,200);
  assert.equal(sql(`SELECT count(*) FROM deedlight_event_private.c76_bounce_classifications
    WHERE event_id='msg_c76_undetermined_http01' AND bounce_type='Undetermined'`),'1');
  assert.equal(sql(`SELECT s.pending_unmatched::text FROM public.delivery_recipient_state s
    JOIN public.delivery_provider_submissions p USING(recipient_fingerprint)
    WHERE p.provider_email_id='provider-c76-uncertain-001'`),'true');
  cases++;
  console.log('Signed Undetermined bounce -> PostgreSQL classification + fail-closed temporary hold: PASS');

  // An informational success after the unknown bounce must not release it.
  const lateSuccess=signedEvent('msg_c76_late_delivery001','email.delivered',{
    email_id:'provider-c76-uncertain-001',to:[secondEmail],
  });
  assert.equal((await fetch(url,{method:'POST',headers:lateSuccess.headers,body:lateSuccess.body})).status,200);
  assert.equal(sql(`SELECT s.pending_unmatched::text FROM public.delivery_recipient_state s
    JOIN public.delivery_provider_submissions p USING(recipient_fingerprint)
    WHERE p.provider_email_id='provider-c76-uncertain-001'`),'true');
  cases++;
  console.log('Out-of-order delivery success cannot release Undetermined recipient hold: PASS');

  assert.equal(providerCalls.length,1,'Only one synthetic external send ever attempted');
  console.log(JSON.stringify({c76_end_to_end:'pass',cases,synthetic_provider_attempts:providerCalls.length,
    db_rpc_calls:rpcCalls.length,real_provider_calls:0}));
} finally {
  await new Promise((ok)=>reader.close(ok));
}

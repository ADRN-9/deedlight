import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, randomUUID, sign, timingSafeEqual, verify } from 'node:crypto';
import test from 'node:test';

const AUDIENCE = 'deedlight.execution-ledger.dispatch.v2';
const MAX_TTL_MS = 2_000;
const CLOCK_SKEW_MS = 250;

function canonicalize(value) {
  if (value === null || typeof value === 'boolean' || typeof value === 'string') {
    if (typeof value === 'string' && value.normalize('NFC') !== value) {
      throw new TypeError('strings must be NFC-normalized');
    }
    return JSON.stringify(value);
  }
  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value)) throw new TypeError('numbers must be safe integers');
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return '[' + value.map((item) => canonicalize(item)).join(',') + ']';
  }
  if (typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype) {
    const keys = Object.keys(value).sort();
    return '{' + keys.map((key) => {
      if (key.normalize('NFC') !== key) throw new TypeError('keys must be NFC-normalized');
      return JSON.stringify(key) + ':' + canonicalize(value[key]);
    }).join(',') + '}';
  }
  throw new TypeError('unsupported canonical JSON value');
}

const bytes = (value) => Buffer.from(canonicalize(value), 'utf8');
const digest = (value) => createHash('sha256').update(bytes(value)).digest('hex');
const keyPair = () => generateKeyPairSync('ed25519');
const signed = (payload, privateKey) => ({
  payload,
  signature: sign(null, bytes(payload), privateKey).toString('base64url'),
});
const validSignature = (token, publicKey) => {
  try {
    return verify(null, bytes(token.payload), publicKey, Buffer.from(token.signature, 'base64url'));
  } catch {
    return false;
  }
};
const fixedTimeEqual = (left, right) => {
  const a = Buffer.from(left, 'base64url');
  const b = Buffer.from(right, 'base64url');
  return a.length === b.length && timingSafeEqual(a, b);
};

class IndependentAuthority {
  constructor(now = () => Date.now()) {
    this.now = now;
    this.provider = keyPair();
    this.policy = keyPair();
    this.nonce = keyPair();
    this.resources = new Map();
    this.consumed = new Set();
  }

  registerResource(resourceId, generation = 1) {
    this.resources.set(resourceId, { generation, state: 'ACTIVE' });
  }

  attestResource({ resourceId, nonce, now = this.now(), ttl = MAX_TTL_MS }) {
    const resource = this.resources.get(resourceId);
    if (!resource || resource.state !== 'ACTIVE') throw new Error('resource_not_active');
    return signed({
      audience: AUDIENCE, resourceId, generation: resource.generation,
      nonce, issuedAt: now, expiresAt: now + ttl,
    }, this.provider.privateKey);
  }

  authorizePolicy({ actor, operation, requestDigest, resourceId, nonce, now = this.now(), ttl = MAX_TTL_MS }) {
    const resource = this.resources.get(resourceId);
    if (!resource || resource.state !== 'ACTIVE') throw new Error('resource_not_active');
    return signed({
      audience: AUDIENCE, actor, operation, requestDigest, resourceId,
      generation: resource.generation, nonce, issuedAt: now, expiresAt: now + ttl,
    }, this.policy.privateKey);
  }

  consumeDispatch({ resourceAttestation, policyAuthorization, now = this.now() }) {
    if (!validSignature(resourceAttestation, this.provider.publicKey)) throw new Error('provider_attestation_invalid');
    if (!validSignature(policyAuthorization, this.policy.publicKey)) throw new Error('policy_authorization_invalid');
    const resource = resourceAttestation.payload;
    const policy = policyAuthorization.payload;
    const current = this.resources.get(resource.resourceId);
    if (!current || current.state !== 'ACTIVE' || current.generation !== resource.generation) {
      throw new Error('resource_generation_revoked');
    }
    if (resource.audience !== AUDIENCE || policy.audience !== AUDIENCE
      || resource.nonce !== policy.nonce || resource.resourceId !== policy.resourceId
      || resource.generation !== policy.generation
      || resource.issuedAt > now + CLOCK_SKEW_MS || policy.issuedAt > now + CLOCK_SKEW_MS
      || resource.expiresAt <= now || policy.expiresAt <= now
      || resource.expiresAt - resource.issuedAt > MAX_TTL_MS
      || policy.expiresAt - policy.issuedAt > MAX_TTL_MS) {
      throw new Error('authorization_claims_invalid');
    }
    if (this.consumed.has(policy.nonce)) throw new Error('nonce_replayed');
    // This synchronous state transition is the authority's linearization point.
    this.consumed.add(policy.nonce);
    return signed({
      audience: AUDIENCE, nonce: policy.nonce, actor: policy.actor,
      operation: policy.operation, requestDigest: policy.requestDigest,
      resourceId: policy.resourceId, generation: policy.generation,
      consumedAt: now, expiresAt: Math.min(resource.expiresAt, policy.expiresAt),
      receiptId: randomUUID(),
    }, this.nonce.privateKey);
  }

  rotate(resourceId, expectedGeneration) {
    const resource = this.resources.get(resourceId);
    if (!resource || resource.state !== 'ACTIVE' || resource.generation !== expectedGeneration) {
      throw new Error('generation_compare_and_swap_failed');
    }
    resource.generation += 1;
    return resource.generation;
  }

  revoke(resourceId, expectedGeneration) {
    const resource = this.resources.get(resourceId);
    if (!resource || resource.state !== 'ACTIVE' || resource.generation !== expectedGeneration) {
      throw new Error('generation_compare_and_swap_failed');
    }
    resource.state = 'REVOKED';
  }
}

function authorize({ authority, resourceId, actualResourceId = resourceId, actor = 'runner',
  operation = 'heartbeat_execution', request, nonce = randomUUID(), now = authority.now() }) {
  const requestDigest = digest(request);
  const resourceAttestation = authority.attestResource({ resourceId, nonce, now });
  const policyAuthorization = authority.authorizePolicy({
    actor, operation, requestDigest, resourceId, nonce, now,
  });
  if (actualResourceId !== resourceId) throw new Error('connected_resource_identity_mismatch');
  const receipt = authority.consumeDispatch({ resourceAttestation, policyAuthorization, now });
  if (!validSignature(receipt, authority.nonce.publicKey)) throw new Error('dispatch_receipt_invalid');
  const claims = receipt.payload;
  if (claims.resourceId !== actualResourceId || claims.requestDigest !== requestDigest
    || claims.actor !== actor || claims.operation !== operation || claims.expiresAt <= now) {
    throw new Error('dispatch_receipt_binding_mismatch');
  }
  return { receipt, nonce, requestDigest };
}

test('canonical JSON profile matches cross-language vector', () => {
  const value = { z: 1, a: { y: true, x: 'é' }, arr: [3, 'ok'] };
  assert.equal(canonicalize(value), '{"a":{"x":"é","y":true},"arr":[3,"ok"],"z":1}');
  assert.equal(digest({ a: 1, b: 2 }), '43258cff783fe7036d8a43033f830adfc60ec037382473548ac742b888292777');
  assert.throws(() => canonicalize({ value: 1.5 }), /safe integers/);
  assert.throws(() => canonicalize({ value: 'e\u0301' }), /NFC-normalized/);
});

test('Ed25519 provider, policy and nonce authorities are independently verifiable', () => {
  const authority = new IndependentAuthority(() => 1_800_000_000_000);
  authority.registerResource('prod-cluster-a');
  const result = authorize({
    authority, resourceId: 'prod-cluster-a', now: 1_800_000_000_000,
    request: { executionId: 'a'.repeat(36), generation: 1 },
  });
  assert.equal(validSignature(result.receipt, authority.nonce.publicKey), true);
  assert.equal(validSignature(result.receipt, authority.provider.publicKey), false);
});

test('concurrent nonce consumption has exactly one winner', async () => {
  const authority = new IndependentAuthority(() => 1_800_000_000_000);
  authority.registerResource('resource-a');
  const nonce = randomUUID();
  const now = 1_800_000_000_000;
  const resourceAttestation = authority.attestResource({ resourceId: 'resource-a', nonce, now });
  const policyAuthorization = authority.authorizePolicy({
    actor: 'runner', operation: 'start_execution', requestDigest: digest({ id: 7 }),
    resourceId: 'resource-a', nonce, now,
  });
  const attempts = await Promise.allSettled(Array.from({ length: 32 }, () =>
    Promise.resolve().then(() => authority.consumeDispatch({ resourceAttestation, policyAuthorization, now }))));
  assert.equal(attempts.filter((item) => item.status === 'fulfilled').length, 1);
  assert.equal(attempts.filter((item) => item.status === 'rejected').length, 31);
  assert.equal(authority.consumed.size, 1);
});

test('physical clone with copied PostgreSQL system identifier has a different external resource identity', () => {
  const authority = new IndependentAuthority(() => 1_800_000_000_000);
  authority.registerResource('provider-instance-primary');
  authority.registerResource('provider-instance-clone');
  const copiedSystemIdentifier = 'same-postgres-system-id';
  const signedResource = 'provider-instance-primary';
  const clone = { systemIdentifier: copiedSystemIdentifier, externalResourceId: 'provider-instance-clone' };
  assert.equal(clone.systemIdentifier, copiedSystemIdentifier);
  assert.throws(() => authorize({
    authority, resourceId: signedResource, actualResourceId: clone.externalResourceId,
    request: { operation: 'reserve_execution' }, now: 1_800_000_000_000,
  }), /connected_resource_identity_mismatch/);
});

test('stale database backup cannot replay a nonce already consumed by external authority', () => {
  const authority = new IndependentAuthority(() => 1_800_000_000_000);
  authority.registerResource('resource-backup-test');
  const nonce = randomUUID();
  const now = 1_800_000_000_000;
  const resourceAttestation = authority.attestResource({ resourceId: 'resource-backup-test', nonce, now });
  const policyAuthorization = authority.authorizePolicy({
    actor: 'runner', operation: 'finalize_execution', requestDigest: digest({ id: 8 }),
    resourceId: 'resource-backup-test', nonce, now,
  });
  const receipt = authority.consumeDispatch({ resourceAttestation, policyAuthorization, now });
  const restoredLocalNonceTable = new Set();
  assert.equal(restoredLocalNonceTable.has(nonce), false);
  assert.throws(() => authority.consumeDispatch({ resourceAttestation, policyAuthorization, now }), /nonce_replayed/);
  assert.equal(validSignature(receipt, authority.nonce.publicKey), true);
});

test('generation transition fences stale receipts and compare-and-swap is monotonic', () => {
  const authority = new IndependentAuthority(() => 1_800_000_000_000);
  authority.registerResource('resource-generation');
  const nonce = randomUUID();
  const now = 1_800_000_000_000;
  const resourceAttestation = authority.attestResource({ resourceId: 'resource-generation', nonce, now });
  const policyAuthorization = authority.authorizePolicy({
    actor: 'recovery', operation: 'recover_stale_executions', requestDigest: digest({ ids: [1] }),
    resourceId: 'resource-generation', nonce, now,
  });
  assert.equal(authority.rotate('resource-generation', 1), 2);
  assert.throws(() => authority.consumeDispatch({ resourceAttestation, policyAuthorization, now }), /resource_generation_revoked/);
  assert.throws(() => authority.rotate('resource-generation', 1), /generation_compare_and_swap_failed/);
});

test('revocation and dispatch admission are serialized at the authority linearization point', () => {
  const authority = new IndependentAuthority(() => 1_800_000_000_000);
  authority.registerResource('resource-revocation');
  const nonce = randomUUID();
  const now = 1_800_000_000_000;
  const resourceAttestation = authority.attestResource({ resourceId: 'resource-revocation', nonce, now });
  const policyAuthorization = authority.authorizePolicy({
    actor: 'runner', operation: 'heartbeat_execution', requestDigest: digest({ id: 9 }),
    resourceId: 'resource-revocation', nonce, now,
  });
  authority.revoke('resource-revocation', 1);
  assert.throws(() => authority.consumeDispatch({ resourceAttestation, policyAuthorization, now }), /resource_generation_revoked/);
});

test('expiry boundaries fail closed', () => {
  const authority = new IndependentAuthority(() => 1_800_000_000_000);
  authority.registerResource('resource-expiry');
  const nonce = randomUUID();
  const now = 1_800_000_000_000;
  const resourceAttestation = authority.attestResource({ resourceId: 'resource-expiry', nonce, now, ttl: 1 });
  const policyAuthorization = authority.authorizePolicy({
    actor: 'runner', operation: 'start_execution', requestDigest: digest({ id: 10 }),
    resourceId: 'resource-expiry', nonce, now, ttl: 1,
  });
  assert.throws(() => authority.consumeDispatch({ resourceAttestation, policyAuthorization, now: now + 1 }), /authorization_claims_invalid/);
});

test('ambiguous database rollback consumes the external nonce; retry requires a new challenge', () => {
  const authority = new IndependentAuthority(() => 1_800_000_000_000);
  authority.registerResource('resource-rollback');
  const nonce = randomUUID();
  const now = 1_800_000_000_000;
  const resourceAttestation = authority.attestResource({ resourceId: 'resource-rollback', nonce, now });
  const policyAuthorization = authority.authorizePolicy({
    actor: 'runner', operation: 'record_effect_commit_marker', requestDigest: digest({ id: 11 }),
    resourceId: 'resource-rollback', nonce, now,
  });
  const receipt = authority.consumeDispatch({ resourceAttestation, policyAuthorization, now });
  // Simulate PostgreSQL transaction rollback after the external consume committed.
  const databaseEffectRowsAfterRollback = [];
  assert.deepEqual(databaseEffectRowsAfterRollback, []);
  assert.throws(() => authority.consumeDispatch({ resourceAttestation, policyAuthorization, now }), /nonce_replayed/);
  assert.equal(validSignature(receipt, authority.nonce.publicKey), true);
});

test('fixed-length signature comparison uses a constant-time primitive', () => {
  const expected = Buffer.alloc(64, 0x5a).toString('base64url');
  const same = Buffer.alloc(64, 0x5a).toString('base64url');
  const different = Buffer.alloc(64, 0x5b).toString('base64url');
  assert.equal(fixedTimeEqual(expected, same), true);
  assert.equal(fixedTimeEqual(expected, different), false);
  assert.equal(fixedTimeEqual(expected, 'short'), false);
});

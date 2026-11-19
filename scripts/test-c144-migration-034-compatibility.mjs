import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";

const MAIN = "ce82b3fdf1a73510de70e3729a487d4ae00e66e3";
const C103 = "136e467927269196a97d028feb6f00987f30b257";
const C105 = "4029f0c69833efb42d3fd4950dfb18958d0bafb9";
const C107 = "40626848e8bc8354edcaf0099b26a18a90af4166";
const run = (args) => execFileSync("git", args, { encoding: "utf8" }).trim();
const at = (ref, path) => run(["show", ref + ":" + path]);
const hasAncestor = (sha) => assert.equal(run(["merge-base", sha, "HEAD"]), sha,
  "Required source ancestor missing: " + sha);

hasAncestor(MAIN);
hasAncestor(C103);
hasAncestor(C105);
hasAncestor(C107);

const legacy = at(MAIN, "lib/data/offerings.ts");
const corrected = at(C103, "lib/data/offerings.ts");
const legacyAdminColumns = legacy.match(/const adminOfferingColumns = \`([\s\S]*?)\`;/)?.[1];
const memberColumns = corrected.match(/const ownerOfferingColumns = \`([\s\S]*?)\`;/)?.[1];
assert.ok(legacyAdminColumns, "Legacy application projection missing");
assert.ok(memberColumns, "C103 owner projection missing");
assert.match(legacyAdminColumns, /\bmoderation_note\b/);
assert.match(legacyAdminColumns, /\bopen_report_count\b/);
assert.match(legacy, /export async function getAdminOfferings[\s\S]*?\.from\("offerings"\)[\s\S]*?\.select\(adminOfferingColumns\)/);
assert.match(legacy, /export async function getMyOffering[\s\S]*?\.from\("offerings"\)[\s\S]*?\.select\(adminOfferingColumns\)/);
assert.match(legacy, /export async function getMyOfferings[\s\S]*?\.from\("offerings"\)[\s\S]*?\.select\(adminOfferingColumns\)/);
assert.doesNotMatch(legacy, /\.rpc\("admin_list_offerings"/);

assert.match(memberColumns, /\bowner_feedback\b/);
assert.doesNotMatch(memberColumns, /\bmoderation_note\b|\bopen_report_count\b/);
assert.match(corrected, /export async function getAdminOfferings[\s\S]*?\.rpc\("admin_list_offerings"/);
assert.match(corrected, /export async function getAdminOffering[\s\S]*?\.rpc\("admin_list_offerings"/);
assert.match(corrected, /export async function getMyOffering[\s\S]*?\.select\(ownerOfferingColumns\)/);
assert.match(corrected, /export async function getMyOfferings[\s\S]*?\.select\(ownerOfferingColumns\)/);

const migrationPath = "supabase/migrations/202611150034_c101_member_privacy_boundaries.sql";
const migration = at(C103, migrationPath);
assert.match(migration, /C101 requires the unmodified C79 Offering\/Journey schema/);
assert.match(migration, /to_regprocedure\('public\.admin_list_offerings\(text,integer,uuid\[\]\)'\) IS NOT NULL/);
assert.match(migration, /column_name='owner_feedback'/);
assert.match(migration, /DROP POLICY "offerings_select_public_or_own" ON public\.offerings/);
assert.match(migration, /ADD COLUMN owner_feedback text/);
const memberGrant = migration.match(/GRANT SELECT \(([\s\S]*?)\) ON public\.offerings TO authenticated;/)?.[1];
assert.ok(memberGrant, "C101 member column grant missing");
assert.match(memberGrant, /\bowner_feedback\b/);
assert.doesNotMatch(memberGrant, /\bmoderation_note\b|\bopen_report_count\b/);
assert.match(migration, /CREATE FUNCTION public\.admin_list_offerings/);
assert.match(migration, /IF auth\.uid\(\) IS NULL OR NOT public\.is_admin\(\)/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.admin_list_offerings\(text,integer,uuid\[\]\)\s+TO authenticated,service_role/);
assert.match(migration, /CREATE POLICY c101_daily_reflections_owner_select/);
assert.match(migration, /CREATE POLICY c101_daily_reflections_owner_update/);
assert.match(migration, /CREATE POLICY c101_daily_reflections_owner_delete/);
assert.match(migration, /has_column_privilege\('authenticated','public\.offerings','moderation_note','SELECT'\)/);
assert.match(migration, /has_column_privilege\('authenticated','public\.offerings','open_report_count','SELECT'\)/);

const actions = at(C103, "app/admin/offerings/[id]/actions.ts");
assert.match(actions, /moderation_note:\s*z\.string\(\)\.trim\(\)\.max\(1000\)/);
assert.match(actions, /owner_feedback:\s*z\.string\(\)\.trim\(\)\.max\(1000\)/);
assert.match(actions, /function readModerationDecision[\s\S]*?moderation_note:[\s\S]*?owner_feedback:/);
assert.match(actions, /status: "rejected", \.\.\.notes/);
assert.match(actions, /status: "needs_edit", \.\.\.notes/);
assert.match(actions, /status: "hidden", \.\.\.notes/);
const types = at(C103, "lib/types.ts");
const memberType = types.match(/export type MemberOffering =([\s\S]*?);/)?.[1];
const adminType = types.match(/export type AdminOffering =([\s\S]*?);/)?.[1];
assert.ok(memberType && adminType);
assert.match(memberType, /\bowner_feedback\b/);
assert.doesNotMatch(memberType, /\bmoderation_note\b|\bopen_report_count\b/);
assert.match(adminType, /\bmoderation_note\b/);

const migrationDir = "supabase/migrations";
const files = readdirSync(migrationDir).filter((name) => name.endsWith(".sql")).sort();
assert.equal(files.length, 35, "Unexpected migration inventory; review before release");
const byVersion = new Map();
for (const name of files) {
  const version = name.split("_", 1)[0];
  byVersion.set(version, [...(byVersion.get(version) ?? []), name]);
}
const duplicateVersions = [...byVersion.entries()].filter(([, names]) => names.length > 1);
assert.deepEqual(duplicateVersions, [[
  "202607260007",
  ["202607260007_sprint6_daily_deedlight.sql", "202607260007_sprint7_pwa_daily_engagement.sql"],
]], "Historical migration prefix collision changed; require reconciliation review");
const expectedBlobs = new Map([
  ["202607260007_sprint6_daily_deedlight.sql", "e0c2379255003b8c7bc85a1fab781e23051f5e47"],
  ["202607260007_sprint7_pwa_daily_engagement.sql", "8b051cfce05ea75b1ee7a726864e2ad760f6fe5f"],
  ["202611150034_c101_member_privacy_boundaries.sql", "e01f3ebc390404fdc9eaf67f5c5866067bd71668"],
]);
for (const [name, expected] of expectedBlobs) {
  assert.equal(run(["hash-object", migrationDir + "/" + name]), expected,
    "Historical migration identity changed: " + name);
}

console.log("C144_MIGRATION_034_COMPATIBILITY_PASS");
console.log("MATRIX existing-app/pre-034=compatible-but-privacy-defective");
console.log("MATRIX corrected-app/pre-034=incompatible-owner_feedback-and-admin-RPC-missing");
console.log("MATRIX existing-app/post-034=incompatible-private-column-grants-revoked");
console.log("MATRIX corrected-app/post-034=intended-release-combination");
console.log("MIGRATION_IDENTITY_PASS duplicate-202607260007-preserved; 034-byte-identity-preserved");

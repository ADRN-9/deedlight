import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const expected = [
  "catalog_private_tables_rls",
  "catalog_auth_users_no_browser_select",
  "catalog_moderation_private",
  "catalog_public_projection_columns",
  "anon_private_journey",
  "anon_private_completions",
  "anon_saved_lights",
  "anon_reminder_preferences",
  "anon_newsletter_consent",
  "anon_invitation_attribution",
  "anon_moderation_and_report_details",
  "anon_auth_addresses",
  "anon_base_offerings",
  "anon_profile_opt_in",
  "anon_anonymous_offering_projection",
  "anon_rising_anonymity",
  "anon_weekly_anonymity",
  "anon_public_profile_no_private_fields",
  "anon_admin_functions_denied",
  "owner_private_journey_and_completion",
  "owner_saved_lights",
  "owner_preferences_and_consent",
  "owner_invitation_and_profile",
  "owner_base_offerings_only",
  "owner_invitee_attribution_denied",
  "cross_member_journey_completion",
  "cross_member_saved_lights",
  "cross_member_preferences",
  "cross_member_invitation_and_profile",
  "cross_member_base_offering_private",
  "authenticated_anonymous_author_uuid_denied",
  "authenticated_private_moderation_note_denied",
  "member_moderation_and_auth_denied",
  "member_admin_rpc_denied",
  "admin_moderation_rpc_authorized",
  "admin_context_excludes_private_journey",
  "admin_member_private_journey_denied",
  "admin_private_journey_update_denied",
  "admin_private_journey_delete_denied",
  "c101_admin_fields_column_privilege_closed",
  "c101_legacy_public_select_policy_removed",
  "c101_admin_reflection_policies_removed",
  "c101_public_projection_never_exposes_moderation_note",
  "c101_anon_admin_offerings_rpc_denied",
  "c101_other_member_admin_offerings_rpc_denied",
  "c101_other_member_owner_feedback_denied",
  "c101_admin_internal_moderation_read_allowed",
  "c101_admin_reports_read_allowed",
  "c101_admin_modification_allowed",
  "c101_owner_feedback_visible",
  "c101_owner_cannot_read_internal_moderation_note",
  "c101_owner_cannot_forge_feedback",
  "c101_owner_journey_create",
  "c101_owner_journey_update",
  "c101_owner_journey_delete",
  "c101_owner_original_journey_preserved",
  "c101_owner_offering_edit",
  "c101_owner_offering_edited_pending",
  "c101_owner_offering_remove",
  "c101_owner_offering_hidden_privately",
  "c101_owner_offering_restore",
  "c101_admin_member_suspension_allowed",
  "c101_suspended_new_community_offering_denied",
  "c101_suspended_private_journey_still_owned"
];
assert.equal(expected.length, 64, "64 versioned security cases are mandatory");
assert.equal(new Set(expected).size, expected.length);
const source = readFileSync("scripts/test-c101-member-privacy.sql", "utf8");
const defined = [...source.matchAll(/c83_test\.record\('([^']+)'/g)].map((m) => m[1]);
assert.deepEqual([...defined].sort(), [...expected].sort(), "SQL assertion inventory changed");

const log = readFileSync(process.argv[2], "utf8");
const rows = [...log.matchAll(/\{"status":\s*"(PASS|FAIL)",\s*"scenario":\s*"([^"]+)"\}/g)]
  .map((m) => ({ status: m[1], scenario: m[2] }));
assert.equal(rows.length, expected.length, "Privacy test log must contain all 64 assertions");
assert.equal(new Set(rows.map((x) => x.scenario)).size, expected.length);
assert.deepEqual(rows.map((x) => x.scenario).sort(), [...expected].sort());
assert.ok(rows.every((x) => x.status === "PASS"), "One or more privacy assertions failed");
const summary = log.match(/\{"failed":\s*(\d+),\s*"passed":\s*(\d+),[^\n]*"scenarios":\s*(\d+),\s*"delivery_enabled":\s*false\}/);
assert.ok(summary, "Missing exact safe-environment summary");
assert.deepEqual(summary.slice(1).map(Number), [0,64,64]);
console.log("RELEASE_PRIVACY_INVENTORY_PASS 64/64; all exact C83/C101 scenarios preserved");

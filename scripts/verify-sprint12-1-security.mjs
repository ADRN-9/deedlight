import fs from "node:fs";

const files = {
  migration17: "supabase/migrations/202608130017_sprint12_1_offering_ownership_engagement.sql",
  migration18: "supabase/migrations/202608140018_sprint12_1_owner_removal_guard_hotfix.sql",
  ownerMenu: "components/offerings/offering-owner-menu.tsx",
  detailPage: "app/offerings/[id]/page.tsx",
  reactions: "components/offerings/reaction-buttons.tsx",
  savedLights: "lib/data/saved-lights.ts",
};

function read(path) {
  if (!fs.existsSync(path)) {
    throw new Error(`Required security file is missing: ${path}`);
  }
  return fs.readFileSync(path, "utf8");
}

function requireMatch(name, text, pattern) {
  if (!pattern.test(text)) {
    throw new Error(`Security assertion failed: ${name}`);
  }
  console.log(`PASS: ${name}`);
}

function requireCount(name, text, pattern, minimum) {
  const matches = text.match(pattern) ?? [];
  if (matches.length < minimum) {
    throw new Error(
      `Security assertion failed: ${name}; expected at least ${minimum}, found ${matches.length}`,
    );
  }
  console.log(`PASS: ${name}`);
}

function requireAbsent(name, text, pattern) {
  if (pattern.test(text)) {
    throw new Error(`Security assertion failed: ${name}`);
  }
  console.log(`PASS: ${name}`);
}

const migration17 = read(files.migration17);
const migration18 = read(files.migration18);
const ownerMenu = read(files.ownerMenu);
const detailPage = read(files.detailPage);
const reactions = read(files.reactions);
const savedLights = read(files.savedLights);

requireMatch(
  "Offering saves use the privacy-minimized public projection",
  migration17,
  /create policy\s+"saved_lights_insert_own_published_source"[\s\S]*?from public\.offerings_public op/i,
);

requireMatch(
  "Cross-member reactions authorize through the public projection",
  migration17,
  /create policy\s+"reactions_insert_own_on_approved"[\s\S]*?from public\.offerings_public op/i,
);

requireCount(
  "Both save and reaction authorization reference offerings_public",
  migration17,
  /from public\.offerings_public op/gi,
  2,
);

requireMatch(
  "Owner edit RPC is SECURITY DEFINER with a constrained search_path",
  migration17,
  /create or replace function public\.update_own_offering\([\s\S]*?security definer\s+set search_path = public, pg_temp/i,
);

requireMatch(
  "Owner edit blocks rejected Offerings",
  migration17,
  /if v_offering\.status = 'rejected' then[\s\S]*?cannot be resubmitted/i,
);

requireMatch(
  "Owner edit blocks moderator-hidden Offerings",
  migration17,
  /v_offering\.status = 'hidden'[\s\S]*?v_offering\.owner_removed_at is null[\s\S]*?cannot be changed from the member editor/i,
);

requireMatch(
  "Restore requires an active, non-suspended profile",
  migration17,
  /create or replace function public\.restore_own_offering\([\s\S]*?p\.is_suspended = false/i,
);

requireMatch(
  "Restore only accepts owner-removed hidden Offerings",
  migration17,
  /v_offering\.status <> 'hidden' or v_offering\.owner_removed_at is null/i,
);

requireMatch(
  "Owner-removed rows are constrained to hidden status",
  migration18,
  /constraint offerings_owner_removed_hidden[\s\S]*?owner_removed_at is null[\s\S]*?status = 'hidden'/i,
);

requireMatch(
  "Removal hotfix blocks rejected Offerings",
  migration18,
  /if v_offering\.status = 'rejected' then[\s\S]*?cannot be changed from the member controls/i,
);

requireMatch(
  "Removal hotfix blocks moderator-hidden Offerings",
  migration18,
  /v_offering\.status = 'hidden'[\s\S]*?v_offering\.owner_removed_at is null[\s\S]*?cannot be changed from the member controls/i,
);

requireMatch(
  "Removal hotfix is idempotent only for already owner-removed rows",
  migration18,
  /if v_offering\.owner_removed_at is not null then\s+return p_offering_id;/i,
);

requireMatch(
  "Removal RPC execution is revoked before authenticated re-grant",
  migration18,
  /revoke all[\s\S]*?on function public\.remove_own_offering\(uuid\)[\s\S]*?from public, anon, authenticated;[\s\S]*?grant execute[\s\S]*?to authenticated;/i,
);

requireMatch(
  "Owner UI does not offer Remove for rejected content",
  ownerMenu,
  /const canRemove\s*=\s*offering\.status !== "rejected"\s*&&\s*!removedByOwner\s*&&\s*!moderatorHidden;/m,
);

requireMatch(
  "Detail ownership is derived through the private owner lookup",
  detailPage,
  /getMyOffering\(id\)/,
);

requireAbsent(
  "Detail page never derives ownership from public user_id",
  detailPage,
  /offering\.user_id/,
);

requireMatch(
  "Saved Offering hydration reads offerings_public",
  savedLights,
  /\.from\("offerings_public"\)/,
);

requireMatch(
  "Reaction hydration recognizes inspired_me",
  reactions,
  /value === "inspired_me"/,
);

requireMatch(
  "Reaction hydration recognizes i_did_this_too",
  reactions,
  /value === "i_did_this_too"/,
);

requireAbsent(
  "Legacy inspired reaction key is not accepted",
  reactions,
  /value === "inspired"/,
);

requireAbsent(
  "Legacy did_too reaction key is not accepted",
  reactions,
  /value === "did_too"/,
);

console.log("Sprint 12.1 security assertions: PASS");

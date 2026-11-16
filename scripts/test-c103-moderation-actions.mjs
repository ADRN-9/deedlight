#!/usr/bin/env node
// Run actual server actions with synthetic Supabase and Next.js boundary adapters.
// This is an application-layer integration test, not a live Supabase HTTP test.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import vm from "node:vm";
import ts from "typescript";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";

const nodeRequire = createRequire(import.meta.url);
const offeringId = "83030000-0000-4000-8000-000000000001";
const ownerId = "83000000-0000-4000-8000-000000000001";
const adminId = "83000000-0000-4000-8000-000000000003";
const strangerId = "83000000-0000-4000-8000-000000000002";
const staffMarker = "C103-STAFF-ONLY-REPORTER-IDENTITY";
const memberMessage = "Please revise this Offering without identifying anyone.";

if (process.env.ADMIN_EMAILS) {
  throw new Error("C103 test refuses external admin-email configuration");
}

let row;
let activeUser;
let suspended;
let redirects = [];
let revalidations = [];

function reset() {
  row = {
    id: offeringId,
    user_id: ownerId,
    offering_type: "gratitude",
    title: "A quiet kindness",
    body: "A gentle synthetic Offering for testing.",
    status: "pending",
    moderation_note: null,
    owner_feedback: null,
    is_anonymous: true,
    allow_reflections: true,
    created_at: "2026-11-15T00:00:00.000Z",
    updated_at: "2026-11-15T00:00:00.000Z",
    published_at: null,
    open_report_count: 0,
    owner_removed_at: null,
    bless_count: 0,
    inspired_count: 0,
    carried_forward_count: 0,
    reflection_count: 0,
    bless_score: 0,
  };
  activeUser = { id: adminId, email: "c103-admin@example.test" };
  suspended = false;
  redirects = [];
  revalidations = [];
}

function profileFor(userId) {
  return {
    user_id: userId,
    role: userId === adminId ? "admin" : "member",
    is_suspended: userId === adminId && suspended,
    username: userId === ownerId ? "c103-owner" : "c103-admin",
    display_name: userId === ownerId ? "Owner" : "Moderator",
    avatar_url: null,
  };
}

function project(record, columns) {
  if (columns === "*" || !columns) return { ...record };
  const names = columns.split(",").map((s) => s.trim());
  const result = {};
  for (const name of names) {
    if (!/^[a-z][a-z0-9_]*$/i.test(name)) {
      throw new Error("Unexpected synthetic projection expression");
    }
    if (!(name in record)) continue;
    result[name] = record[name];
  }
  return result;
}

function isDatabaseAdmin() {
  return activeUser?.id === adminId && !suspended;
}

class Query {
  constructor(table, operation = "select", payload = null) {
    this.table = table;
    this.operation = operation;
    this.payload = payload;
    this.columns = "*";
    this.filters = [];
    this.max = Infinity;
  }
  select(columns) { this.columns = columns; return this; }
  eq(name, value) { this.filters.push((record) => record[name] === value); return this; }
  in(name, values) { this.filters.push((record) => values.includes(record[name])); return this; }
  order() { return this; }
  limit(count) { this.max = count; return this; }
  matching() {
    let records = this.table === "profiles"
      ? [profileFor(ownerId), profileFor(adminId), profileFor(strangerId)]
      : this.table === "offerings_public"
        ? [{
            ...row, user_id: row.is_anonymous ? null : row.user_id,
            author_name: null, author_username: null
          }]
        : [row];
    return records.filter((x) => this.filters.every((fn) => fn(x))).slice(0, this.max);
  }
  async maybeSingle() {
    if (this.operation === "update") {
      if (!isDatabaseAdmin() || this.table !== "offerings") {
        return { data: null, error: { code: "42501", message: "Access denied" } };
      }
      const old = this.matching()[0];
      if (!old) return { data: null, error: null };
      Object.assign(row, this.payload);
      return { data: project(row, this.columns), error: null };
    }
    const data = this.matching()[0] ?? null;
    return { data: data ? project(data, this.columns) : null, error: null };
  }
  async result() {
    return { data: this.matching().map((x) => project(x, this.columns)), error: null };
  }
  then(resolve, reject) { return this.result().then(resolve, reject); }
}

const client = {
  auth: { async getUser() { return { data: { user: activeUser } }; } },
  from(table) {
    return {
      select(columns) { return new Query(table).select(columns); },
      update(payload) { return new Query(table, "update", payload); },
    };
  },
  rpc(name, args) {
    if (name !== "admin_list_offerings") throw new Error("Unexpected RPC " + name);
    const query = new Query("offerings");
    if (!isDatabaseAdmin()) {
      return { async maybeSingle() { return { data: null, error: { code: "42501" } }; } };
    }
    if (args.p_ids) query.in("id", args.p_ids);
    return query;
  },
};

const redirect = (location) => {
  redirects.push(location);
  throw Object.assign(new Error("redirect requested"), { redirectTo: location });
};
const link = ({ href, children, ...rest }) =>
  React.createElement("a", { ...rest, href }, children);
const iconModule = new Proxy({}, {
  get(_target, name) {
    if (typeof name !== "string") return undefined;
    return ({ children, ...props }) => React.createElement("svg", {
      "aria-hidden": "true",
      ...props,
    }, children);
  },
});

const mocks = {
  "next/navigation": { redirect, notFound: () => { throw new Error("not found"); } },
  "next/cache": { revalidatePath: (path) => revalidations.push(path) },
  "next/link": { __esModule: true, default: link },
  "zod": nodeRequire("zod"),
  "react/jsx-runtime": nodeRequire("react/jsx-runtime"),
  "lucide-react": iconModule,
  "@/lib/supabase/server": { createClient: async () => client },
  "@/components/offerings/offering-owner-menu": {
    OfferingOwnerMenu: () => null,
  },
  "@/components/ui/pending-submit-button": {
    PendingSubmitButton: ({ children, ...props }) => React.createElement("button", props, children),
  },
  "./fallback": { fallbackOfferings: [] },
};

function loadSource(path, overrides = {}) {
  const js = ts.transpileModule(readFileSync(path, "utf8"), {
    fileName: path,
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      jsx: ts.JsxEmit.ReactJSX,
      target: ts.ScriptTarget.ES2022,
      esModuleInterop: true,
    },
    reportDiagnostics: true,
  });
  const diagnostics = js.diagnostics?.filter((d) => d.category === ts.DiagnosticCategory.Error);
  assert.equal(diagnostics?.length ?? 0, 0, path + " must transpile");
  const module = { exports: {} };
  const merged = { ...mocks, ...overrides };
  const localRequire = (name) => {
    if (Object.prototype.hasOwnProperty.call(merged, name)) return merged[name];
    throw new Error("Unexpected dependency: " + name);
  };
  const context = {
    module, exports: module.exports, require: localRequire,
    process, Date, URL, console, FormData,
  };
  vm.runInNewContext(js.outputText, context, { filename: path, timeout: 5000 });
  return module.exports;
}

reset();
const adminAccess = loadSource("lib/auth/admin-access.ts");
const auth = loadSource("lib/auth/admin.ts", {
  "@/lib/auth/admin-access": adminAccess,
});
const actions = loadSource("app/admin/offerings/[id]/actions.ts", {
  "@/lib/auth/admin": auth,
});
const dataApi = loadSource("lib/data/offerings.ts");
const ownerUi = loadSource("components/journey/my-offerings.tsx");
const adminPage = loadSource("app/admin/offerings/[id]/page.tsx", {
  "@/lib/auth/admin": auth,
  "@/lib/data/offerings": {
    getAdminOffering: async () => ({ ...row }),
    getReportsForOffering: async () => [],
  },
  "./actions": actions,
});

const actionModes = [
  ["rejectOffering", "rejected"],
  ["requestOfferingEdit", "needs_edit"],
  ["hideOffering", "hidden"],
];

function form(note, feedback) {
  const f = new FormData();
  f.set("id", offeringId);
  if (note !== undefined) f.set("moderation_note", note);
  if (feedback !== undefined) f.set("owner_feedback", feedback);
  return f;
}

async function perform(action, note, feedback) {
  await assert.rejects(actions[action](form(note, feedback)),
    (error) => error?.redirectTo ===
      "/admin/offerings/" + offeringId + "?updated=" +
      ({ rejectOffering: "rejected", requestOfferingEdit: "needs_edit", hideOffering: "hidden" }[action]));
  assert.ok(revalidations.includes("/journey") === false);
  assert.ok(revalidations.includes("/admin/offerings"));
}

async function ownerProjection() {
  activeUser = { id: ownerId, email: "c103-owner@example.test" };
  const own = await dataApi.getMyOffering(offeringId);
  const list = await dataApi.getMyOfferings(10);
  assert.equal(list.length, 1);
  assert.deepEqual(Object.keys(own).sort(), Object.keys(list[0]).sort());
  assert.ok(!("moderation_note" in own), "owner props must never contain staff moderation_note");
  assert.ok(!("open_report_count" in own), "owner props must never contain staff report count");
  return own;
}

function ownerHtml(own) {
  return renderToStaticMarkup(React.createElement(ownerUi.MyOfferings, {
    offerings: [own], filter: "all",
  }));
}

for (const [action, state] of actionModes) {
  test(action + ": distinct internal and member feedback, owner-safe render", async () => {
    reset();
    await perform(action, staffMarker, memberMessage);
    assert.equal(row.status, state);
    assert.equal(row.moderation_note, staffMarker);
    assert.equal(row.owner_feedback, memberMessage);
    assert.ok(redirects.every((path) => !path.includes(staffMarker)));
    const owner = await ownerProjection();
    assert.equal(owner.owner_feedback, memberMessage);
    assert.ok(!JSON.stringify(owner).includes(staffMarker));
    const html = ownerHtml(owner);
    assert.match(html, /Feedback from moderators:/);
    assert.ok(html.includes(memberMessage));
    assert.ok(!html.includes(staffMarker));
    assert.ok(!html.includes("moderation_note"));
    activeUser = { id: adminId, email: "c103-admin@example.test" };
    const adminRow = await dataApi.getAdminOffering(offeringId);
    assert.equal(adminRow.moderation_note, staffMarker);
  });

  test(action + ": internal-only note clears prior owner feedback", async () => {
    reset();
    row.owner_feedback = "old member note";
    await perform(action, staffMarker, undefined);
    assert.equal(row.status, state);
    assert.equal(row.moderation_note, staffMarker);
    assert.equal(row.owner_feedback, null);
    const owner = await ownerProjection();
    assert.equal(owner.owner_feedback, null);
    assert.ok(!ownerHtml(owner).includes(staffMarker));
    assert.ok(!ownerHtml(owner).includes("old member note"));
  });

  test(action + ": feedback-only transition never inherits an old internal note", async () => {
    reset();
    row.moderation_note = "prior staff context";
    await perform(action, undefined, memberMessage);
    assert.equal(row.status, state);
    assert.equal(row.moderation_note, null);
    assert.equal(row.owner_feedback, memberMessage);
    assert.ok(!ownerHtml(await ownerProjection()).includes("prior staff context"));
  });

  test(action + ": empty fields clear both without implicit templates", async () => {
    reset();
    row.moderation_note = staffMarker;
    row.owner_feedback = "previous feedback";
    await perform(action, undefined, undefined);
    assert.equal(row.status, state);
    assert.equal(row.moderation_note, null);
    assert.equal(row.owner_feedback, null);
    const html = ownerHtml(await ownerProjection());
    assert.ok(!html.includes(staffMarker));
    assert.ok(!html.includes("previous feedback"));
  });

  test(action + ": rejects oversized private and public fields independently", async () => {
    for (const field of ["moderation_note", "owner_feedback"]) {
      reset();
      const f = form(field === "moderation_note" ? "x".repeat(1001) : "", field === "owner_feedback" ? "y".repeat(1001) : "");
      await assert.rejects(actions[action](f),
        (e) => e?.redirectTo?.includes("Moderation%20fields%20must%20be%20text"));
      assert.equal(row.status, "pending");
      assert.equal(row.moderation_note, null);
      assert.equal(row.owner_feedback, null);
    }
  });
}

test("unauthorized member role claim cannot invoke any moderation action", async () => {
  for (const [action] of actionModes) {
    reset();
    activeUser = {
      id: strangerId, email: "stranger@example.test",
      app_metadata: { role: "admin" },
      user_metadata: { role: "admin" },
    };
    await assert.rejects(actions[action](form(staffMarker, memberMessage)),
      (e) => e?.redirectTo === "/today");
    assert.equal(row.status, "pending");
    assert.equal(row.owner_feedback, null);
    assert.equal(row.moderation_note, null);
  }
});

test("suspended database admin loses all moderation-action privileges", async () => {
  for (const [action] of actionModes) {
    reset();
    suspended = true;
    await assert.rejects(actions[action](form(staffMarker, memberMessage)),
      (e) => e?.redirectTo === "/today");
    assert.equal(row.status, "pending");
    assert.equal(row.owner_feedback, null);
    assert.equal(row.moderation_note, null);
  }
});

test("admin detail forms present separately labeled and bound textarea fields", async () => {
  reset();
  const element = await adminPage.default({
    params: Promise.resolve({ id: offeringId }),
    searchParams: Promise.resolve({}),
  });
  const html = renderToStaticMarkup(element);
  assert.equal((html.match(/name="moderation_note"/g) ?? []).length >= 3, true);
  assert.equal((html.match(/name="owner_feedback"/g) ?? []).length, 3);
  assert.equal((html.match(/Internal moderation note · Staff only/g) ?? []).length, 3);
  assert.equal((html.match(/Feedback from moderators · Visible to the member/g) ?? []).length, 3);
  for (const prefix of ["request-edit", "reject", "hide"]) {
    assert.ok(html.includes('id="' + prefix + '-internal"'));
    assert.ok(html.includes('id="' + prefix + '-feedback"'));
    assert.ok(html.includes('for="' + prefix + '-internal"'));
    assert.ok(html.includes('for="' + prefix + '-feedback"'));
  }
});

test("member-facing projection excludes private staff fields and public view redacts anonymous identity", async () => {
  reset();
  row.moderation_note = staffMarker;
  row.owner_feedback = memberMessage;
  const owner = await ownerProjection();
  assert.ok(!JSON.stringify(owner).includes(staffMarker));
  assert.ok(!ownerHtml(owner).includes(staffMarker));
  const publicView = await dataApi.getOffering(offeringId);
  assert.equal(publicView.user_id, null);
  assert.ok(!JSON.stringify(publicView).includes(staffMarker));
  assert.ok(!("owner_feedback" in publicView));
});

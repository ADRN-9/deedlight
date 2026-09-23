import fs from "node:fs";

const migrationPath = "supabase/migrations/202609230020_delivery_reliability_hardening.sql";
const aggregatePath = "supabase/run_in_sql_editor_all.sql";

const migration = fs.readFileSync(migrationPath, "utf8").trim();
const aggregate = fs.readFileSync(aggregatePath, "utf8");

if (aggregate.includes(migration)) {
  console.log("Aggregate SQL already contains the canonical migration.");
  process.exit(0);
}

const next = `${aggregate.trimEnd()}\n\n${migration}\n`;
fs.writeFileSync(aggregatePath, next, "utf8");
console.log("Appended canonical delivery reliability migration to aggregate SQL.");

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { normalizeMigrationHistoryRows, validateMigrationHistoryRows } from "./reconcile-migration-evidence.mjs";

const inputPath = process.argv[2];
assert(inputPath, "usage: node scripts/test-migration-history-sql-output.mjs <psql-tuples-file>");
const manifest = JSON.parse(readFileSync("supabase/migration-inventory.json", "utf8"));
const raw = readFileSync(inputPath, "utf8").trimEnd();
const tuples = raw === "" ? [] : raw.split(/\r?\n/).map((line) => line.split("\t"));
const rows = normalizeMigrationHistoryRows(tuples);
const problems = validateMigrationHistoryRows(rows, manifest);
assert.deepEqual(problems, [], "normalized SQL output must satisfy analyzer migration-history validation");
process.stdout.write(JSON.stringify({ complete: true, rows }, null, 2) + "\n");

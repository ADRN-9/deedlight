"""Offline safety checks only — NOT PostgreSQL parser or execution tests."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
HEAD = "c983e2ed8b93c935139c935343261570ecea6978"
SQL_FILES = (ROOT / "00_preflight.sql", ROOT / "01_catalog_audit.sql")

for path in SQL_FILES:
    sql = path.read_text(encoding="utf-8")
    # SQL comments are not execution; strip before checking dangerous tokens.
    executable = "\n".join(line.split("--", 1)[0] for line in sql.splitlines())
    assert re.search(r"\bBEGIN\s+TRANSACTION\s+ISOLATION\s+LEVEL\s+REPEATABLE\s+READ\s*,\s*READ\s+ONLY\s*;", executable, re.I), path.name
    assert re.search(r"\bROLLBACK\s*;\s*$", executable, re.I), path.name
    assert HEAD in sql
    for operation in (
        r"\bINSERT\s+INTO\b", r"\bUPDATE\s+\S+\s+SET\b",
        r"\bDELETE\s+FROM\b", r"\bALTER\s+(TABLE|FUNCTION|ROLE|POLICY)\b",
        r"\bCREATE\s+(TABLE|FUNCTION|POLICY|ROLE|INDEX|TRIGGER)\b",
        r"\bDROP\s+", r"\bTRUNCATE\s+", r"\bCOPY\s+",
        r"\bGRANT\s+\w+\s+ON\b", r"\bREVOKE\s+\w+\s+ON\b",
        r"\bCALL\s+\w+\s*\(", r"\bDO\s+\$\$",
        r"\bpg_read_file\b", r"\bpg_ls_dir\b",
        r"\bFROM\s+(?:public|auth|supabase_migrations)\.",
        r"\bJOIN\s+(?:public|auth|supabase_migrations)\."
    ):
        assert not re.search(operation, executable, re.I), (path.name, operation)
    assert "pg_catalog.coalesce" not in executable
    assert "pg_catalog.pg_proc" in executable
    assert "source_sha" in executable

body = SQL_FILES[1].read_text()
for signature in (
    "public.begin_delivery_transport(uuid,uuid,text)",
    "public.begin_delivery_transport(uuid,uuid)",
    "public.enqueue_due_daily_reminders(timestamptz,integer)",
    "public.enqueue_weekly_goodness_delivery(date,timestamptz,integer)",
    "public.enqueue_current_weekly_goodness_if_curated(timestamptz,integer)",
    "public.retry_delivery_job(uuid,uuid,timestamptz,text)",
    "public.handle_new_user()",
):
    assert signature in body, signature
for required in (
    "pg_catalog.pg_policy", "pg_catalog.pg_constraint", "pg_catalog.pg_attribute",
    "pg_catalog.has_function_privilege", "pg_catalog.has_table_privilege",
    "pg_catalog.pg_get_expr", "pg_catalog.pg_get_constraintdef",
    "md5(p.prosrc)", "relrowsecurity", "UNIQUE(kind,user_id,delivery_key)",
    "migration_history:recorded_versions", "production_identity:independent_project_reference",
):
    assert required in body, required

schema = json.loads((ROOT / "audit_record.schema.json").read_text())
assert schema["properties"]["source_sha"]["const"] == HEAD
assert schema["properties"]["status"]["enum"] == [
    "VERIFIED", "FAILED", "BLOCKED", "UNKNOWN"
]
assert set(schema["required"]) == {"source_sha", "invariant", "status", "expected", "actual"}

print("PASS — two SQL files explicitly use read-only transactions and ROLLBACK")
print("PASS — no direct customer/migration table reads or mutating SQL tokens in executable text")
print("PASS — selected catalog checks and reviewed function signatures present")
print("PASS — evidence JSON schema and exact pinned source SHA coherent")
print("NOTE — this is static inspection; PostgreSQL parse/execution and fixtures NOT RUN")

#!/usr/bin/env bash
set -euo pipefail
bash scripts/guard-supabase-migration-target.sh
link_file="supabase/.temp/project-ref"
if [[ ! -f "$link_file" ]]; then
  echo "::error::Supabase project link missing; refuse unverified db push." >&2
  exit 1
fi
linked="$(<"$link_file")"
if [[ "$linked" != "$SUPABASE_PROJECT_REF" ]]; then
  echo "::error::Linked project differs from approved non-Production target." >&2
  exit 1
fi

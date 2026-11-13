#!/usr/bin/env bash
set -euo pipefail

ref="${SUPABASE_PROJECT_REF:-}"
if [[ ! "${ref}" =~ ^[a-z]{20}$ ]]; then
  echo "::error::A valid non-Production Supabase project ref is required." >&2
  exit 1
fi

if [[ "${ref}" == "xaipiovflxomcbfwtwmu" ]]; then
  echo "::error::DeedLight Production migration history is unreconciled; db push is forbidden." >&2
  exit 1
fi

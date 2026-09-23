#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/ADRN-9/deedlight"
RUNNER_NAME="ENG-DEV1"
RUNNER_LABEL="deedlight-dev"
RUNNER_DIR="${HOME}/actions-runner"

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  echo "This bootstrap expects Linux x86_64." >&2
  exit 1
fi

for command in curl jq git tar; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Missing required command: ${command}" >&2
    echo "Install prerequisites first: sudo apt-get update && sudo apt-get install -y curl jq git ca-certificates" >&2
    exit 1
  fi
done

mkdir -p "${RUNNER_DIR}"
cd "${RUNNER_DIR}"

if [[ -f .runner || -f .credentials ]]; then
  echo "Runner directory is already configured. Remove the old ephemeral registration before reusing it." >&2
  exit 1
fi

RUNNER_VERSION="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
if [[ -z "${RUNNER_VERSION}" || "${RUNNER_VERSION}" == "null" ]]; then
  echo "Could not resolve the latest GitHub Actions runner version." >&2
  exit 1
fi

ARCHIVE="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${ARCHIVE}"

if [[ ! -f "${ARCHIVE}" ]]; then
  curl -fL --retry 3 --retry-delay 2 -o "${ARCHIVE}" "${DOWNLOAD_URL}"
fi

tar xzf "${ARCHIVE}"

printf 'Paste the one-time repository runner registration token (input hidden): '
IFS= read -rs RUNNER_TOKEN
printf '\n'

if [[ -z "${RUNNER_TOKEN}" ]]; then
  echo "Runner registration token is required." >&2
  exit 1
fi

./config.sh \
  --url "${REPO_URL}" \
  --token "${RUNNER_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABEL}" \
  --work "_work" \
  --unattended \
  --ephemeral \
  --replace

unset RUNNER_TOKEN

echo "Ephemeral runner configured. Starting it now."
echo "It will accept one matching GitHub Actions job and then deregister automatically."
exec ./run.sh

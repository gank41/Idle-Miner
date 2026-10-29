#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 1 || ! -f "$1/updates/stable.json" || ! -f "$1/index.html" ]]; then
  echo 'Usage: bash Deployment/deploy.sh VERIFIED_STAGING_DIRECTORY' >&2
  exit 1
fi
node "$(dirname "$0")/verify-site.mjs" "$1"
"${WRANGLER_BIN:-wrangler}" pages deploy "$1" --force --project-name idle-miner --branch main --commit-dirty=true

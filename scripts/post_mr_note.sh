#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo >&2 "Usage: $0 <markdown-file>"
  exit 2
fi

body_file="$1"

if [ -z "${CI_MERGE_REQUEST_IID:-}" ]; then
  echo "No CI_MERGE_REQUEST_IID; skipping MR note."
  cat "$body_file"
  exit 0
fi

token="${GITLAB_API_TOKEN:-${CI_JOB_TOKEN:-}}"
if [ -z "$token" ]; then
  echo >&2 "No GITLAB_API_TOKEN or CI_JOB_TOKEN available; printing feedback instead."
  cat "$body_file"
  exit 0
fi

api_url="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/merge_requests/${CI_MERGE_REQUEST_IID}/notes"

header_name="PRIVATE-TOKEN"
if [ -z "${GITLAB_API_TOKEN:-}" ]; then
  header_name="JOB-TOKEN"
fi

jq -n --rawfile body "$body_file" '{body: $body}' > /tmp/openbeagle_mr_note.json

curl --fail-with-body \
  --request POST \
  --header "${header_name}: ${token}" \
  --header "Content-Type: application/json" \
  --data @/tmp/openbeagle_mr_note.json \
  "$api_url"
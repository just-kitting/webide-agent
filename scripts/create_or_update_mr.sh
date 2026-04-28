#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo >&2 "Usage: $0 <review-markdown-file>"
  exit 2
fi

body_file="$1"

if [ -z "${CI_COMMIT_BRANCH:-}" ]; then
  echo >&2 "No CI_COMMIT_BRANCH; cannot create MR."
  cat "$body_file"
  exit 0
fi

target_branch="${OPENBEAGLE_AGENT_TARGET_BRANCH:-${CI_DEFAULT_BRANCH:-main}}"

if [ "$CI_COMMIT_BRANCH" = "$target_branch" ]; then
  echo "Current branch is target branch; not creating MR."
  cat "$body_file"
  exit 0
fi

token="${GITLAB_API_TOKEN:-${CI_JOB_TOKEN:-}}"
if [ -z "$token" ]; then
  echo >&2 "No GITLAB_API_TOKEN or CI_JOB_TOKEN available; printing review instead."
  cat "$body_file"
  exit 0
fi

header_name="PRIVATE-TOKEN"
if [ -z "${GITLAB_API_TOKEN:-}" ]; then
  header_name="JOB-TOKEN"
fi

project_api="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}"
encoded_source_branch="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$CI_COMMIT_BRANCH")"

existing_mr_json="$(curl --silent --fail-with-body \
  --header "${header_name}: ${token}" \
  "${project_api}/merge_requests?state=opened&source_branch=${encoded_source_branch}" || true)"

existing_iid="$(printf '%s' "$existing_mr_json" | jq -r '.[0].iid // empty' 2>/dev/null || true)"

title_prefix="${OPENBEAGLE_AGENT_MR_TITLE_PREFIX:-Agent review}"
title="${title_prefix}: ${CI_COMMIT_BRANCH}"

description="$(cat "$body_file")"

if [ -n "$existing_iid" ]; then
  echo "Updating existing MR !${existing_iid}"

  jq -n \
    --arg description "$description" \
    '{description: $description}' > /tmp/openbeagle_mr_update.json

  curl --fail-with-body \
    --request PUT \
    --header "${header_name}: ${token}" \
    --header "Content-Type: application/json" \
    --data @/tmp/openbeagle_mr_update.json \
    "${project_api}/merge_requests/${existing_iid}"

  jq -n \
    --arg body "$description" \
    '{body: $body}' > /tmp/openbeagle_mr_note.json

  curl --fail-with-body \
    --request POST \
    --header "${header_name}: ${token}" \
    --header "Content-Type: application/json" \
    --data @/tmp/openbeagle_mr_note.json \
    "${project_api}/merge_requests/${existing_iid}/notes"

else
  echo "Creating MR from ${CI_COMMIT_BRANCH} to ${target_branch}"

  jq -n \
    --arg source_branch "$CI_COMMIT_BRANCH" \
    --arg target_branch "$target_branch" \
    --arg title "$title" \
    --arg description "$description" \
    '{
      source_branch: $source_branch,
      target_branch: $target_branch,
      title: $title,
      description: $description,
      remove_source_branch: false,
      squash: false
    }' > /tmp/openbeagle_mr_create.json

  curl --fail-with-body \
    --request POST \
    --header "${header_name}: ${token}" \
    --header "Content-Type: application/json" \
    --data @/tmp/openbeagle_mr_create.json \
    "${project_api}/merge_requests"
fi
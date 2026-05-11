#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo >&2 "Usage: $0 <review-markdown-file>"
  exit 2
fi

body_file="$1"

if [ ! -f "$body_file" ]; then
  echo >&2 "Review markdown file does not exist: $body_file"
  exit 2
fi

if [ -z "${CI_COMMIT_BRANCH:-}" ]; then
  echo >&2 "No CI_COMMIT_BRANCH; cannot create feedback MR."
  cat "$body_file"
  exit 1
fi

if [ -z "${CI_COMMIT_SHA:-}" ]; then
  echo >&2 "No CI_COMMIT_SHA; cannot create feedback branch."
  cat "$body_file"
  exit 1
fi

if [ -z "${GITLAB_API_TOKEN:-}" ]; then
  echo >&2 "GITLAB_API_TOKEN is not set; cannot create feedback MR."
  echo >&2 "Use a project access token with API/write access."
  cat "$body_file"
  exit 1
fi

target_branch="$CI_COMMIT_BRANCH"
target_sha="$CI_COMMIT_SHA"
short_sha="${CI_COMMIT_SHORT_SHA:-${CI_COMMIT_SHA:0:8}}"

feedback_branch="${OPENBEAGLE_AGENT_FEEDBACK_BRANCH:-llm-feedback-${short_sha}}"
feedback_file="${OPENBEAGLE_AGENT_FEEDBACK_FILE:-OPENBEAGLE_AGENT_REVIEW.md}"
title="${OPENBEAGLE_AGENT_MR_TITLE:-LLM feedback for ${short_sha}}"

project_api="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}"
token="$GITLAB_API_TOKEN"

urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

api() {
  local method="$1"
  local url="$2"
  local data_file="${3:-}"
  local response_file
  response_file="$(mktemp)"

  local args=(
    --silent
    --show-error
    --location
    --request "$method"
    --header "PRIVATE-TOKEN: ${token}"
    --output "$response_file"
    --write-out "%{http_code}"
  )

  if [ -n "$data_file" ]; then
    args+=(--header "Content-Type: application/json" --data @"$data_file")
  fi

  local status
  set +e
  status="$(curl "${args[@]}" "$url")"
  local rc=$?
  set -e

  if [ "$rc" -ne 0 ]; then
    echo >&2 "curl failed: exit=$rc method=$method url=$url"
    rm -f "$response_file"
    exit 1
  fi

  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo >&2 "GitLab API failed: status=$status method=$method url=$url"
    echo >&2 "Response:"
    cat "$response_file" >&2 || true
    echo >&2

    case "$status" in
      401)
        echo >&2 "Hint: token is missing, expired, protected-but-not-available, or not valid for this project."
        ;;
      403)
        echo >&2 "Hint: token is valid but lacks permission to push/create MRs."
        ;;
      409|400)
        echo >&2 "Hint: branch/MR may already exist, or the commit request was invalid."
        ;;
    esac

    rm -f "$response_file"
    exit 1
  fi

  cat "$response_file"
  rm -f "$response_file"
}

echo "Creating feedback MR for ${target_branch}@${short_sha}"
echo "Feedback branch: ${feedback_branch}"
echo "MR direction: ${feedback_branch} -> ${target_branch}"

review_body="$(cat "$body_file")"

commit_payload="$(mktemp)"
jq -n \
  --arg branch "$feedback_branch" \
  --arg start_sha "$target_sha" \
  --arg commit_message "Add LLM feedback for ${short_sha}" \
  --arg file_path "$feedback_file" \
  --arg content "$review_body" \
  '{
    branch: $branch,
    start_sha: $start_sha,
    force: true,
    commit_message: $commit_message,
    actions: [
      {
        action: "update",
        file_path: $file_path,
        content: $content
      }
    ]
  }' > "$commit_payload"

echo "Writing feedback commit..."

set +e
commit_json="$(api POST "${project_api}/repository/commits" "$commit_payload" 2> /tmp/openbeagle_commit_error.log)"
commit_rc=$?
set -e

if [ "$commit_rc" -ne 0 ]; then
  if grep -qi "file does not exist\|A file with this name doesn't exist\|does not exist" /tmp/openbeagle_commit_error.log; then
    echo "Feedback file does not exist yet; creating it instead."

    jq -n \
      --arg branch "$feedback_branch" \
      --arg start_sha "$target_sha" \
      --arg commit_message "Add LLM feedback for ${short_sha}" \
      --arg file_path "$feedback_file" \
      --arg content "$review_body" \
      '{
        branch: $branch,
        start_sha: $start_sha,
        force: true,
        commit_message: $commit_message,
        actions: [
          {
            action: "create",
            file_path: $file_path,
            content: $content
          }
        ]
      }' > "$commit_payload"

    commit_json="$(api POST "${project_api}/repository/commits" "$commit_payload")"
  else
    cat /tmp/openbeagle_commit_error.log >&2
    rm -f "$commit_payload"
    exit "$commit_rc"
  fi
fi

rm -f "$commit_payload" /tmp/openbeagle_commit_error.log

feedback_commit_sha="$(printf '%s' "$commit_json" | jq -r '.id // empty')"
echo "Feedback commit: ${feedback_commit_sha:-created}"

encoded_feedback_branch="$(urlencode "$feedback_branch")"
encoded_target_branch="$(urlencode "$target_branch")"

existing_mr_json="$(
  api GET "${project_api}/merge_requests?state=opened&source_branch=${encoded_feedback_branch}&target_branch=${encoded_target_branch}"
)"

existing_iid="$(printf '%s' "$existing_mr_json" | jq -r '.[0].iid // empty')"

mr_description="$(cat "$body_file")"

if [ -n "$existing_iid" ]; then
  echo "Updating existing MR !${existing_iid}"

  update_payload="$(mktemp)"
  jq -n \
    --arg title "$title" \
    --arg description "$mr_description" \
    '{
      title: $title,
      description: $description
    }' > "$update_payload"

  updated_json="$(api PUT "${project_api}/merge_requests/${existing_iid}" "$update_payload")"
  rm -f "$update_payload"

  web_url="$(printf '%s' "$updated_json" | jq -r '.web_url // empty')"
  echo "Updated MR !${existing_iid}${web_url:+: ${web_url}}"
else
  echo "Creating MR"

  create_payload="$(mktemp)"
  jq -n \
    --arg source_branch "$feedback_branch" \
    --arg target_branch "$target_branch" \
    --arg title "$title" \
    --arg description "$mr_description" \
    '{
      source_branch: $source_branch,
      target_branch: $target_branch,
      title: $title,
      description: $description,
      remove_source_branch: true,
      squash: false
    }' > "$create_payload"

  created_json="$(api POST "${project_api}/merge_requests" "$create_payload")"
  rm -f "$create_payload"

  created_iid="$(printf '%s' "$created_json" | jq -r '.iid // empty')"
  web_url="$(printf '%s' "$created_json" | jq -r '.web_url // empty')"
  echo "Created MR !${created_iid}${web_url:+: ${web_url}}"
fi
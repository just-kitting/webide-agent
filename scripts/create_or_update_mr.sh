#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo >&2 "Usage: $0 <review-markdown-file>"
  exit 2
fi

body_file="$1"

if [ ! -f "$body_file" ]; then
  echo >&2 "Review markdown file does not exist: ${body_file}"
  exit 2
fi

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo >&2 "Required CI variable is not set: ${name}"
    exit 2
  fi
}

urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

print_api_error_hints() {
  local status="$1"

  case "$status" in
    401)
      cat >&2 <<'EOF'
Hint: GitLab returned 401 Unauthorized.
- Verify GITLAB_API_TOKEN is set in CI/CD variables and is not expired or revoked.
- If the variable is protected, this pipeline must run on a protected branch/tag.
- CI_JOB_TOKEN is intentionally not used here because it cannot create/update MRs.
EOF
      ;;
    403)
      cat >&2 <<'EOF'
Hint: GitLab returned 403 Forbidden.
- The token authenticated, but does not have enough permission.
- Use a project access token with the api scope and a role that can create MRs.
- If the source or target branch is protected, check branch protection rules.
EOF
      ;;
    404)
      cat >&2 <<'EOF'
Hint: GitLab returned 404 Not Found.
- Check CI_PROJECT_ID, source branch, and target branch.
- The token must have access to this project and both branches must exist.
EOF
      ;;
    409|422)
      cat >&2 <<'EOF'
Hint: GitLab rejected the merge request request.
- There might already be an open MR for this source/target pair.
- The source branch might have no commits to merge into the target branch.
- The source or target branch name might be invalid for this project.
EOF
      ;;
  esac
}

api_json() {
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

  local http_code
  set +e
  http_code="$(curl "${args[@]}" "$url")"
  local curl_rc=$?
  set -e

  if [ "$curl_rc" -ne 0 ]; then
    echo >&2 "GitLab API request failed before receiving an HTTP response."
    echo >&2 "curl_exit=${curl_rc} method=${method} url=${url}"
    rm -f "$response_file"
    exit 1
  fi

  if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
    echo >&2 "GitLab API request failed."
    echo >&2 "status=${http_code} method=${method} url=${url}"
    echo >&2 "Response body:"
    cat "$response_file" >&2 || true
    echo >&2
    print_api_error_hints "$http_code"
    rm -f "$response_file"
    exit 1
  fi

  cat "$response_file"
  rm -f "$response_file"
}

require_var CI_API_V4_URL
require_var CI_PROJECT_ID

default_branch="${CI_DEFAULT_BRANCH:-main}"
pipeline_branch="${CI_COMMIT_BRANCH:-}"
legacy_branch="${OPENBEAGLE_AGENT_TARGET_BRANCH:-}"

# Preferred names:
#   OPENBEAGLE_AGENT_MR_SOURCE_BRANCH = branch containing the agent changes
#   OPENBEAGLE_AGENT_MR_TARGET_BRANCH = branch the MR should merge into
#
# Backward compatibility:
#   If a pipeline runs on the default branch and OPENBEAGLE_AGENT_TARGET_BRANCH
#   is a different branch, treat that legacy variable as the source branch.
source_branch="${OPENBEAGLE_AGENT_MR_SOURCE_BRANCH:-${OPENBEAGLE_AGENT_SOURCE_BRANCH:-}}"
if [ -z "$source_branch" ] &&
   [ -n "$legacy_branch" ] &&
   [ -n "$pipeline_branch" ] &&
   [ "$pipeline_branch" = "$default_branch" ] &&
   [ "$legacy_branch" != "$default_branch" ]; then
  source_branch="$legacy_branch"
fi

if [ -z "$source_branch" ]; then
  source_branch="$pipeline_branch"
fi

target_branch="${OPENBEAGLE_AGENT_MR_TARGET_BRANCH:-${OPENBEAGLE_AGENT_DESTINATION_BRANCH:-}}"
if [ -z "$target_branch" ]; then
  if [ -n "$legacy_branch" ] && [ "$source_branch" = "$pipeline_branch" ]; then
    # Original behavior for feature-branch pipelines:
    # current branch -> configured target.
    target_branch="$legacy_branch"
  elif [ -n "$pipeline_branch" ] && [ "$source_branch" != "$pipeline_branch" ]; then
    # Bot-branch behavior:
    # configured source branch -> branch that triggered the pipeline.
    target_branch="$pipeline_branch"
  else
    target_branch="$default_branch"
  fi
fi

if [ -z "$source_branch" ]; then
  echo >&2 "Could not determine MR source branch. Set OPENBEAGLE_AGENT_MR_SOURCE_BRANCH."
  cat "$body_file"
  exit 1
fi

if [ -z "$target_branch" ]; then
  echo >&2 "Could not determine MR target branch. Set OPENBEAGLE_AGENT_MR_TARGET_BRANCH."
  cat "$body_file"
  exit 1
fi

if [ "$source_branch" = "$target_branch" ]; then
  echo "Source and target branches are both '${source_branch}'; not creating MR."
  cat "$body_file"
  exit 0
fi

token="${GITLAB_API_TOKEN:-}"
if [ -z "$token" ]; then
  cat >&2 <<'EOF'
GITLAB_API_TOKEN is not set; cannot create or update a merge request.
Create a project access token with the api scope, store it as GITLAB_API_TOKEN,
and make sure the variable is available to this pipeline.

The generated review follows.
EOF
  cat "$body_file"

  if [ "${OPENBEAGLE_AGENT_MR_OPTIONAL:-false}" = "true" ] ||
     [ "${OPENBEAGLE_AGENT_MR_OPTIONAL:-false}" = "1" ]; then
    exit 0
  fi

  exit 1
fi

project_api="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}"
encoded_source_branch="$(urlencode "$source_branch")"
encoded_target_branch="$(urlencode "$target_branch")"

echo "MR direction: ${source_branch} -> ${target_branch}"
echo "Checking GitLab API access..."
api_json GET "$project_api" >/tmp/openbeagle_project.json

echo "Checking source branch '${source_branch}'..."
source_branch_json="$(api_json GET "${project_api}/repository/branches/${encoded_source_branch}")"

echo "Checking target branch '${target_branch}'..."
target_branch_json="$(api_json GET "${project_api}/repository/branches/${encoded_target_branch}")"

source_sha="$(printf '%s' "$source_branch_json" | jq -r '.commit.id // empty')"
target_sha="$(printf '%s' "$target_branch_json" | jq -r '.commit.id // empty')"

if [ -n "$source_sha" ] && [ "$source_sha" = "$target_sha" ]; then
  echo "Source and target branches point to the same commit (${source_sha}); not creating MR."
  cat "$body_file"
  exit 0
fi

echo "Looking for existing open MR from ${source_branch} to ${target_branch}..."
existing_mr_json="$(
  api_json GET "${project_api}/merge_requests?state=opened&source_branch=${encoded_source_branch}&target_branch=${encoded_target_branch}&per_page=20"
)"

existing_iid="$(
  printf '%s' "$existing_mr_json" |
    jq -r --arg source "$source_branch" --arg target "$target_branch" '
      map(select(.source_branch == $source and .target_branch == $target)) | .[0].iid // empty
    '
)"

title_prefix="${OPENBEAGLE_AGENT_MR_TITLE_PREFIX:-Agent review}"
title="${OPENBEAGLE_AGENT_MR_TITLE:-${title_prefix}: ${source_branch} -> ${target_branch}}"

if [ -n "$existing_iid" ]; then
  echo "Updating existing MR !${existing_iid}"

  update_payload="$(mktemp)"
  jq -n \
    --rawfile description "$body_file" \
    --arg title "$title" \
    '{title: $title, description: $description}' > "$update_payload"

  updated_json="$(api_json PUT "${project_api}/merge_requests/${existing_iid}" "$update_payload")"
  rm -f "$update_payload"

  if [ "${OPENBEAGLE_AGENT_POST_UPDATE_NOTE:-true}" != "false" ] &&
     [ "${OPENBEAGLE_AGENT_POST_UPDATE_NOTE:-true}" != "0" ]; then
    note_payload="$(mktemp)"
    jq -n \
      --rawfile body "$body_file" \
      '{body: $body}' > "$note_payload"

    api_json POST "${project_api}/merge_requests/${existing_iid}/notes" "$note_payload" >/tmp/openbeagle_mr_note.json
    rm -f "$note_payload"
  fi

  web_url="$(printf '%s' "$updated_json" | jq -r '.web_url // empty')"
  echo "Updated MR !${existing_iid}${web_url:+: ${web_url}}"
else
  echo "Creating MR from ${source_branch} to ${target_branch}"

  create_payload="$(mktemp)"
  jq -n \
    --arg source_branch "$source_branch" \
    --arg target_branch "$target_branch" \
    --arg title "$title" \
    --rawfile description "$body_file" \
    '{
      source_branch: $source_branch,
      target_branch: $target_branch,
      title: $title,
      description: $description,
      remove_source_branch: false,
      squash: false
    }' > "$create_payload"

  created_json="$(api_json POST "${project_api}/merge_requests" "$create_payload")"
  rm -f "$create_payload"

  created_iid="$(printf '%s' "$created_json" | jq -r '.iid // empty')"
  web_url="$(printf '%s' "$created_json" | jq -r '.web_url // empty')"
  echo "Created MR !${created_iid}${web_url:+: ${web_url}}"
fi
#!/usr/bin/env bash
set -euo pipefail

zero_sha="0000000000000000000000000000000000000000"
empty_tree_sha="4b825dc642cb6eb9a060e54bf8d69288fbee4904"

commit_sha="${CI_COMMIT_SHA:-HEAD}"
commit_sha="$(git rev-parse "$commit_sha")"

branch="${CI_COMMIT_BRANCH:-${CI_DEFAULT_BRANCH:-}}"

has_commit() {
  git cat-file -e "${1}^{commit}" 2>/dev/null
}

base_sha="${CI_COMMIT_BEFORE_SHA:-}"

# For normal pushes to main, GitLab gives us the previous tip of main.
# That is exactly what we want: review the change that just landed.
if [ -n "$base_sha" ] && [ "$base_sha" != "$zero_sha" ]; then
  if ! has_commit "$base_sha"; then
    # Shallow clones may not have the previous commit locally.
    # Fetch a bit more history for the current branch, but do not compare
    # against any other branch.
    if [ -n "$branch" ]; then
      git fetch --no-tags origin "$branch" --depth=100 >/dev/null 2>&1 || true
    fi
  fi
else
  base_sha=""
fi

# Fallback: review the current commit against its first parent.
if [ -z "$base_sha" ] || ! has_commit "$base_sha"; then
  base_sha="$(git rev-parse "${commit_sha}^" 2>/dev/null || true)"
fi

# Root commit fallback.
if [ -z "$base_sha" ] || ! has_commit "$base_sha"; then
  base_sha="$empty_tree_sha"
fi

echo >&2 "Collecting commit context"
echo >&2 "Branch: ${branch:-unknown}"
echo >&2 "Range: ${base_sha}..${commit_sha}"

changed_files="$(git diff --name-only "$base_sha" "$commit_sha" 2>/dev/null || true)"
diff_stat="$(git diff --stat "$base_sha" "$commit_sha" 2>/dev/null || true)"
compact_diff="$(git diff --unified=2 "$base_sha" "$commit_sha" 2>/dev/null | sed -n '1,1000p' || true)"

if [ "$base_sha" = "$empty_tree_sha" ]; then
  commit_log="$(git log --oneline --decorate --no-merges "$commit_sha" 2>/dev/null | sed -n '1,50p' || true)"
else
  commit_log="$(git log --oneline --decorate --no-merges "$base_sha..$commit_sha" 2>/dev/null | sed -n '1,50p' || true)"
fi

jq -n \
  --arg project "${CI_PROJECT_PATH:-}" \
  --arg project_url "${CI_PROJECT_URL:-}" \
  --arg pipeline_url "${CI_PIPELINE_URL:-}" \
  --arg commit_sha "$commit_sha" \
  --arg branch "$branch" \
  --arg base_sha "$base_sha" \
  --arg compare_range "${base_sha}..${commit_sha}" \
  --arg changed_files "$changed_files" \
  --arg diff_stat "$diff_stat" \
  --arg compact_diff "$compact_diff" \
  --arg commit_log "$commit_log" \
  '{
    project: $project,
    project_url: $project_url,
    pipeline_url: $pipeline_url,

    mode: "commit_review",
    branch: $branch,
    base_sha: $base_sha,
    commit_sha: $commit_sha,
    compare_range: $compare_range,

    commits: ($commit_log | split("\n") | map(select(length > 0))),
    changed_files: ($changed_files | split("\n") | map(select(length > 0))),
    diff_stat: $diff_stat,
    compact_diff: $compact_diff
  }'
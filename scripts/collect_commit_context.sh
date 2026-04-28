#!/usr/bin/env bash
set -euo pipefail

target_branch="${OPENBEAGLE_AGENT_TARGET_BRANCH:-${CI_DEFAULT_BRANCH:-main}}"

git fetch origin "$target_branch" --depth=100 >/dev/null 2>&1 || true

base_sha="$(git merge-base HEAD "origin/$target_branch" 2>/dev/null || true)"
if [ -z "$base_sha" ]; then
  base_sha="${CI_COMMIT_BEFORE_SHA:-}"
fi
if [ -z "$base_sha" ] || [ "$base_sha" = "0000000000000000000000000000000000000000" ]; then
  base_sha="HEAD~1"
fi

changed_files="$(git diff --name-only "$base_sha"...HEAD 2>/dev/null || true)"
diff_stat="$(git diff --stat "$base_sha"...HEAD 2>/dev/null || true)"
compact_diff="$(git diff --unified=2 "$base_sha"...HEAD 2>/dev/null | sed -n '1,1000p' || true)"
commit_log="$(git log --oneline --decorate --no-merges "$base_sha"..HEAD 2>/dev/null | sed -n '1,50p' || true)"

jq -n \
  --arg project "$CI_PROJECT_PATH" \
  --arg project_url "$CI_PROJECT_URL" \
  --arg pipeline_url "${CI_PIPELINE_URL:-}" \
  --arg commit_sha "$CI_COMMIT_SHA" \
  --arg branch "${CI_COMMIT_BRANCH:-}" \
  --arg target_branch "$target_branch" \
  --arg base_sha "$base_sha" \
  --arg changed_files "$changed_files" \
  --arg diff_stat "$diff_stat" \
  --arg compact_diff "$compact_diff" \
  --arg commit_log "$commit_log" \
  '{
    project: $project,
    project_url: $project_url,
    pipeline_url: $pipeline_url,
    commit_sha: $commit_sha,
    branch: $branch,
    target_branch: $target_branch,
    base_sha: $base_sha,
    commits: ($commit_log | split("\n") | map(select(length > 0))),
    changed_files: ($changed_files | split("\n") | map(select(length > 0))),
    diff_stat: $diff_stat,
    compact_diff: $compact_diff
  }'
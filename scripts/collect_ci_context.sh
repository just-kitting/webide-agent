#!/usr/bin/env bash
set -euo pipefail

base_sha="${CI_MERGE_REQUEST_DIFF_BASE_SHA:-}"
target_branch="${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-main}"

if [ -z "$base_sha" ] || [ "$base_sha" = "0000000000000000000000000000000000000000" ]; then
  git fetch origin "$target_branch" --depth=100 >/dev/null 2>&1 || true
  base_sha="$(git merge-base HEAD "origin/$target_branch" 2>/dev/null || true)"
fi

if [ -z "$base_sha" ]; then
  base_sha="HEAD~1"
fi

changed_files="$(git diff --name-only "$base_sha"...HEAD 2>/dev/null || true)"
diff_stat="$(git diff --stat "$base_sha"...HEAD 2>/dev/null || true)"
compact_diff="$(git diff --unified=2 "$base_sha"...HEAD 2>/dev/null | sed -n '1,800p' || true)"

jq -n \
  --arg project "$CI_PROJECT_PATH" \
  --arg project_url "$CI_PROJECT_URL" \
  --arg pipeline_url "${CI_PIPELINE_URL:-}" \
  --arg commit_sha "$CI_COMMIT_SHA" \
  --arg mr_iid "${CI_MERGE_REQUEST_IID:-}" \
  --arg mr_title "${CI_MERGE_REQUEST_TITLE:-}" \
  --arg source_branch "${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-}" \
  --arg target_branch "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}" \
  --arg base_sha "$base_sha" \
  --arg changed_files "$changed_files" \
  --arg diff_stat "$diff_stat" \
  --arg compact_diff "$compact_diff" \
  '{
    project: $project,
    project_url: $project_url,
    pipeline_url: $pipeline_url,
    commit_sha: $commit_sha,
    merge_request: {
      iid: $mr_iid,
      title: $mr_title,
      source_branch: $source_branch,
      target_branch: $target_branch,
      base_sha: $base_sha
    },
    changed_files: ($changed_files | split("\n") | map(select(length > 0))),
    diff_stat: $diff_stat,
    compact_diff: $compact_diff
  }'
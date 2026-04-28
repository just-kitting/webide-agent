---
name: ci-feedback
description: use this when working on the OpenBeagle Web IDE agent's GitLab CI feedback loop, including collecting merge request context, summarizing CI failures, calling local OpenBeagle LLMs, and posting merge request notes. Trigger when asked to modify CI jobs, GitLab runner workflows, MR feedback generation, log summarization, or local-first code review automation.
---

# CI Feedback Skill

## Purpose

Implement and maintain the first OpenBeagle Web IDE agent workflow:

    GitLab MR pipeline
      -> collect compact context
      -> call local LLM
      -> post MR feedback

## Hard rules

- Never commit secrets.
- The initial CI feedback workflow should call local Ollama directly from the GitLab runner on `ollama.openbeagle.org` (ie. 127.0.0.1).
- Do not require a LiteLLM key for the CI feedback workflow.
- Prefer `qwen3-coder:30b` for quality-first CI feedback.
- Use `https://llm.openbeagle.org/v1` only for Web IDE clients, external agents, or later workflows that cannot call local Ollama.
- Do not call cloud LLMs unless the maintainer explicitly requests escalation.
- Keep comments concise and actionable.
- Include this marker:

    <!-- openbeagle-webide-agent:ci-feedback -->

## Inputs

Prefer these GitLab variables:

- `CI_PROJECT_ID`
- `CI_PROJECT_PATH`
- `CI_PROJECT_URL`
- `CI_API_V4_URL`
- `CI_PIPELINE_URL`
- `CI_MERGE_REQUEST_IID`
- `CI_MERGE_REQUEST_TITLE`
- `CI_MERGE_REQUEST_SOURCE_BRANCH_NAME`
- `CI_MERGE_REQUEST_TARGET_BRANCH_NAME`
- `CI_MERGE_REQUEST_DIFF_BASE_SHA`

## Outputs

Generate:

- `out/ci_context.json`
- `out/mr-feedback.md`
- a GitLab merge request note when credentials permit

## Prompting guidance

Ask the local model for:

- summary
- changed-file risk assessment
- likely failures
- suggested next steps

Do not ask the model to review entire repositories. Send compact diffs, targeted logs, and summaries.
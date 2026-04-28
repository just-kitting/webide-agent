---
name: ci-feedback
description: use this when working on the OpenBeagle Web IDE agent's GitLab CI workflow that runs on branch pushes, calls local Ollama on the GPU runner, creates or updates merge requests, and posts agent-generated review questions for human input. Trigger when asked to modify commit-to-MR automation, GitLab runner workflows, branch review generation, MR creation, or local-first CI agent behavior.
---

# CI Feedback Skill

## Purpose

Implement and maintain the first OpenBeagle Web IDE agent workflow:

    branch push
      -> CI on ollama.openbeagle.org
      -> collect compact branch context
      -> call local Ollama
      -> create or update MR
      -> post review feedback/questions

## Hard rules

- Run on branch push pipelines, not merge request pipelines.
- Do not require LiteLLM for the initial CI workflow.
- Call local Ollama directly at `http://127.0.0.1:11434`.
- Prefer `qwen3-coder:30b` for quality-first asynchronous review.
- Never commit secrets.
- Use GitLab CI/CD variables for any GitLab token needed to create MRs.
- Do not call cloud LLMs unless explicitly requested by the maintainer.
- Keep MR comments concise and actionable.
- Include this marker:

    <!-- openbeagle-webide-agent:agent-review -->

## Outputs

Generate:

- `out/commit_context.json`
- `out/agent-review.md`
- a GitLab merge request when credentials permit
- a GitLab merge request note when credentials permit
# OpenBeagle Web IDE Agent

This repository prototypes a local-first coding assistant for GitLab CE and GitLab Web IDE.

## Goals

- Use OpenBeagle-controlled LLM infrastructure.
- Avoid sending repository data to GitLab-hosted AI services.
- Use a GitLab runner on `ollama.openbeagle.org` for model-proximate CI tasks.
- Generate merge request feedback from CI output.
- Grow toward a Web IDE assistant that works in GitLab's browser IDE.

## Non-goals for the first version

- Full autonomous browser agent.
- GitLab Duo integration.
- External LLM calls by default.
- Automatic commits without explicit approval.

## Current local LLM endpoints

Preferred gateway:

    https://llm.openbeagle.org/v1

Model aliases:

    openbeagle-fast
    openbeagle-coder
    openbeagle-stable-coder
    openbeagle-private-cpu
    openbeagle-embed

## CI setup

Required GitLab CI/CD variables:

    OPENBEAGLE_LLM_BASE_URL=https://llm.openbeagle.org/v1
    OPENBEAGLE_LLM_API_KEY=<LiteLLM key>
    OPENBEAGLE_LLM_MODEL=openbeagle-fast

Optional:

    GITLAB_API_TOKEN=<token with permission to post MR notes>

If `GITLAB_API_TOKEN` is unset, scripts should try `CI_JOB_TOKEN`.

## First workflow

A merge request pipeline runs:

    collect_ci_context.sh
      -> ci_context.json

    generate_ci_feedback.py
      -> mr-feedback.md

    post_mr_note.sh
      -> GitLab MR note
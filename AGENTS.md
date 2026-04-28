# AGENTS.md

## Project mission

This repository builds the OpenBeagle Web IDE agent system.

The first milestone is not a full autonomous browser agent. The first milestone is a safe, GitLab-native feedback loop:

1. Use a GitLab runner tied to this project/group and running on `ollama.openbeagle.org`.
2. Access local Ollama/LiteLLM models without sending source code to external AI services.
3. Summarize CI output and changed files.
4. Post useful feedback to a merge request.
5. Use those patterns to later build a Web IDE assistant/agent.

## Architecture

Current intended architecture:

    GitLab CE / Web IDE / project MR
            |
            v
    GitLab CI job on runner at ollama.openbeagle.org
            |
            +--> local model access on the runner
            |    preferred: http://127.0.0.1:11434 or http://127.0.0.1:11435
            |
            +--> optional LiteLLM gateway
                 https://llm.openbeagle.org/v1

Do not assume GitLab Duo is available. This project exists because the deployment uses GitLab CE and must avoid GitLab-hosted AI services.

## Privacy and data handling

Hard requirements:

- Do not send repository contents, diffs, CI logs, prompts, or responses to GitLab-hosted AI, OpenAI, Anthropic, or any other external LLM unless explicitly requested by the maintainer.
- Prefer local models through Ollama or LiteLLM.
- Do not commit API keys, LiteLLM keys, GitLab tokens, SSH keys, cookies, or bearer tokens.
- Use GitLab CI/CD variables for secrets.
- Redact secrets from logs before sending logs to any model.
- Keep prompts compact. Send only relevant files, diffs, errors, and summaries.

Allowed local endpoints:

- `https://llm.openbeagle.org/v1`
- local Ollama endpoints available inside the runner environment
- local helper services explicitly documented in this repository

## First milestones

### Milestone 1: commit-to-MR feedback bot

When a new commit is pushed to a non-default branch:

1. Run CI on the GitLab runner at `ollama.openbeagle.org`.
2. Collect branch context:
   - branch name
   - target branch
   - commit list
   - changed files
   - compact diff
3. Ask local Ollama for review and maintainer questions.
4. Create a merge request if one does not already exist.
5. Update the MR description and post a note with the generated feedback.

This workflow is intended to request additional human input from the user for every new commit or branch.

### Milestone 2: Web IDE assistant prototype

Build a browser-compatible VS Code extension or Web IDE integration that can:

- ask about selected code
- explain the current file
- suggest a patch
- summarize an MR or CI failure
- call only OpenBeagle-controlled endpoints

Do not require a terminal in GitLab Web IDE.

### Milestone 3: agentic workflows

Add controlled workflows:

- apply generated patch to a branch
- create/update MR comments
- run CI
- iterate based on CI output
- escalate only compressed context to ChatGPT when explicitly requested

## Development rules for Codex/agents

When editing this repository:

- Prefer small, reviewable changes.
- Keep shell scripts POSIX-ish and simple.
- Use Python only where JSON handling or API calls become awkward in shell.
- Avoid adding heavyweight frameworks.
- Make every script runnable in CI.
- Include dry-run modes for anything that posts to GitLab.
- Never hard-code `PRIVATE-TOKEN`, `Authorization`, API keys, or personal tokens.
- Treat `CI_JOB_TOKEN` as preferred when sufficient; otherwise document required GitLab CI variables.

## Model routing conventions

For the initial CI feedback workflow, call local Ollama directly from the runner:

- base URL: `http://127.0.0.1:11434`
- default model: `qwen3-coder:30b`

Use the highest-quality local coding model by default. This job is asynchronous and runs in CI, so latency is less important than useful feedback.

Use LiteLLM aliases later for Web IDE and external agent clients:

- `openbeagle-coder`: default coding model through LiteLLM
- `openbeagle-fast`: quick summaries and classification
- `openbeagle-stable-coder`: alternate coding model
- `openbeagle-private-cpu`: local-only CPU route
- `openbeagle-embed`: embeddings for docs/RAG

## Expected CI variables

For the initial CI feedback workflow, no LiteLLM key is required.

The GitLab runner is expected to run on `ollama.openbeagle.org` and call local Ollama directly:

    OPENBEAGLE_OLLAMA_BASE_URL=http://127.0.0.1:11434
    OPENBEAGLE_OLLAMA_MODEL=qwen3-coder:30b

These may be set in `.gitlab-ci.yml` as non-secret defaults.

Optional:

- `GITLAB_API_TOKEN`
  - optional; only needed if `CI_JOB_TOKEN` cannot post MR notes

Later, when building the Web IDE agent, use LiteLLM:

    OPENBEAGLE_LLM_BASE_URL=https://llm.openbeagle.org/v1
    OPENBEAGLE_LLM_API_KEY=<LiteLLM key>
    OPENBEAGLE_LLM_MODEL=openbeagle-coder

## Merge request commenting policy

CI feedback comments must be clearly machine-generated.

Use this marker so the bot can update or identify its own comments later:

    <!-- openbeagle-webide-agent:ci-feedback -->

Feedback should be concise:

- CI status
- likely root cause
- relevant log excerpt
- suggested next action
- model and timestamp

Do not include huge logs in MR comments.
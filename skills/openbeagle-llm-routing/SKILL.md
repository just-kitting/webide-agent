---
name: openbeagle-llm-routing
description: use this when configuring or debugging OpenBeagle local LLM routing through Ollama, LiteLLM, GitLab runners, Web IDE agents, Codex, ZeroClaw, or CI feedback automation. Trigger when asked about ollama.openbeagle.org, llm.openbeagle.org, model aliases, direct local Ollama access, LiteLLM keys, CI model calls, or avoiding external cloud token usage.
---

# OpenBeagle LLM Routing Skill

## Purpose

Use the simplest local route available for the task.

There are two main paths:

1. CI jobs running directly on `ollama.openbeagle.org` should call local Ollama directly.
2. Web IDE clients, Codex, ZeroClaw, desktop IDEs, and external agents should call LiteLLM at `https://llm.openbeagle.org/v1`.

## CI runner path

For CI jobs running on the GitLab runner at `ollama.openbeagle.org`, call Ollama directly:

    http://127.0.0.1:11434/api/chat

Default CI model:

    qwen3-coder:30b

This path does not require a LiteLLM key.

Use this path for:

- merge request CI feedback
- CI log analysis
- asynchronous review comments
- model-proximate jobs running on the GPU runner

Prefer quality over latency for these jobs because the user is not waiting interactively.

## CI environment variables

Use these defaults for CI feedback jobs:

    OPENBEAGLE_OLLAMA_BASE_URL=http://127.0.0.1:11434
    OPENBEAGLE_OLLAMA_MODEL=qwen3-coder:30b

These are not secrets and may be committed as CI defaults.

Do not require these for the initial CI feedback workflow:

    OPENBEAGLE_LLM_API_KEY
    LITELLM_MASTER_KEY

A GitLab token may still be needed to post merge request notes:

    GITLAB_API_TOKEN

Use `CI_JOB_TOKEN` first when it works. Use `GITLAB_API_TOKEN` only when GitLab permissions require it.

## Direct Ollama API shape

Use Ollama chat API:

    POST /api/chat
    Content-Type: application/json

Example body:

    {
      "model": "qwen3-coder:30b",
      "messages": [
        {
          "role": "user",
          "content": "summarize this CI failure"
        }
      ],
      "stream": false,
      "keep_alive": -1,
      "options": {
        "temperature": 0.2
      }
    }

## Web IDE and external agent path

For browser Web IDE agents, Codex, ZeroClaw, desktop VS Code, Cline, Continue, or any client not running on the Ollama host, use the LiteLLM gateway:

    https://llm.openbeagle.org/v1

This path requires a LiteLLM key.

Use this path for:

- Web IDE assistant calls
- Codex and ZeroClaw configuration
- desktop VS Code extensions
- external scripts
- clients that need model aliases instead of raw Ollama model names
- future MCP or context-service integration

## LiteLLM model aliases

Expected aliases:

- `openbeagle-coder`
- `openbeagle-heavy-coder`
- `openbeagle-stable-coder`
- `openbeagle-fast`
- `openbeagle-private-cpu`
- `openbeagle-cpu-large`
- `openbeagle-cpu-reason`
- `openbeagle-embed`

Routing guidance:

- Use `openbeagle-coder` for default coding help through LiteLLM.
- Use `openbeagle-heavy-coder` for deeper coding tasks when available.
- Use `openbeagle-stable-coder` as the alternate coding model.
- Use `openbeagle-fast` for quick interactive summaries and classification.
- Use `openbeagle-private-cpu` for local-only CPU-host tasks.
- Use `openbeagle-embed` only for embeddings/RAG.

Do not use `openbeagle-fast` as the default for asynchronous CI review when the runner can call `qwen3-coder:30b` locally. For CI review, prefer quality and call direct Ollama.

## OpenAI-compatible LiteLLM API shape

Use OpenAI-compatible chat completions:

    POST /v1/chat/completions
    Authorization: Bearer <LiteLLM key>
    Content-Type: application/json

Example body:

    {
      "model": "openbeagle-coder",
      "messages": [
        {
          "role": "user",
          "content": "review this patch"
        }
      ],
      "stream": false
    }

## Security rules

- Never place LiteLLM keys in repository files.
- Never place GitLab tokens, SSH keys, cookies, or bearer tokens in repository files.
- Use CI/CD variables, runtime secret storage, or server-side proxy injection for secrets.
- Avoid direct raw Ollama exposure outside the host or trusted tunnel.
- Prefer direct local Ollama only when the job runs on `ollama.openbeagle.org`.
- Prefer LiteLLM aliases for clients outside the Ollama host.
- Do not send repository contents, CI logs, prompts, or responses to external cloud LLMs unless explicitly requested by the maintainer.

## Escalation policy

Default behavior is local-only.

If extra reasoning is explicitly requested later:

1. Preprocess locally first.
2. Summarize diffs, logs, and relevant files with local Ollama.
3. Send only compressed, relevant context to the external reasoning service.
4. Clearly mark what data leaves OpenBeagle-controlled infrastructure.

Do not add cloud fallback silently.
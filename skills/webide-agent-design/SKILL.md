---
name: webide-agent-design
description: use this when designing the browser-based OpenBeagle Web IDE agent, especially GitLab Web IDE constraints, pure web VS Code extensions, no-terminal workflows, safe patch suggestions, local-only LLM calls, and future MCP/context-service integration.
---

# Web IDE Agent Design Skill

## Design target

Build a browser-compatible assistant for GitLab Web IDE.

The first Web IDE assistant should not require:

- terminal access
- Node-only extension APIs
- local background daemons
- GitLab Duo
- external LLM providers

## First useful commands

Implement these before attempting autonomous workflows:

- Ask About Selection
- Explain Current File
- Suggest Patch
- Generate Commit Message
- Summarize MR or CI Feedback

## Safety model

- Read only the active editor/selection at first.
- Return suggested patches rather than applying them automatically.
- Keep the LiteLLM key out of repository files.
- Call only `https://llm.openbeagle.org/v1` or an OpenBeagle-controlled context service.
- Do not send data to GitLab-hosted AI.

## Future context service

Later, add a server-side context/MCP-style service on `openbeagle.org` that can:

- inspect GitLab repositories
- retrieve docs
- summarize issues and MRs
- collect CI logs
- compress context locally before escalation

The Web IDE extension should call this service over HTTPS. It should not need shell access.
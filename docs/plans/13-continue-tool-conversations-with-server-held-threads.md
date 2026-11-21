---
id: 13
slug: continue-tool-conversations-with-server-held-threads
title: "Continue tool conversations with server held threads"
kind: exec-plan
created_at: 2026-11-21T03:23:04Z
master_plan: "docs/masterplans/4-run-client-tools-across-claude-conversation-turns.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:04Z
---

# Continue tool conversations with server held threads

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

## Purpose / Big Picture

Use the Messages threads beta to send only the new turn and the previous response ID, including when a tool runner supplies the new tool results.

## Progress

- [ ] A thread starts with full history and continues with a delta tied to the last accepted response.
- [ ] A failed or competing continuation cannot silently advance local state or rerun a handler.

## Surprises & Discoveries

## Decision Log

## Outcomes & Retrospective

## Context and Orientation

`src/Claude/Messages.hs` currently replays full history. A server-held thread stores that prefix under a response ID. The preceding runner produces already-correlated tool results. Keep the accepted transcript so a caller can recover from an expired server thread.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) assigns HTTP cleanup and attempt ownership. The [assistant replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) preserves original provider objects and scopes continuation to the originating provider and model. The reviewed reference is TypeScript SDK tag `sdk-v1.12.0` (commit `3edf5eb`), `src/resources/beta/messages/messages.ts` in `mori://anthropics/anthropic-sdk-typescript` (artifact-level URI pending). [Pinned SDK source](https://github.com/anthropics/anthropic-sdk-typescript/blob/sdk-v1.12.0/src/resources/beta/messages/messages.ts)

## Plan of Work

Expose a thread handle bound to its client, model and fixed settings. Send `message-threads-2026-08-12` and `thread.type=create` with the initial system, tools and history. On continue send new messages and `thread={type:continue,previous_message_id:…}`, omit system/tools, retain fixed fields and beta set. Follow the documented pause-turn empty-delta case with scoped validation. Serialize use of the handle and advance its ID only after a completed turn. On a rejected continuation surface recovery with the retained transcript and completed tool results. Make any re-creation an explicit caller decision under the client’s attempt policy.

## Concrete Steps

Extend `test/ToolsSpec.hs`, registered by the prerequisite, through its existing `run` function. Expose any new public module under the Cabal library’s `exposed-modules`. Use `test/Support/Server.hs` for network fixtures and synthetic credentials.

Run from the repository root in the locked development shell.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test claude-hs-test --test-show-details=direct
```

Both commands should exit successfully and Cabal should report the client test suite passed.

## Validation and Acceptance

Capture create plus two continue requests, including client tool results and an ordinary user turn. Check the previous IDs, absence of system/tools and absence of old messages. Exercise pause, expiration, failure after dispatch and overlapping sends. Re-create from confirmed history after a documented thread-not-found response and verify the handler counter stays at one.

## Idempotence and Recovery

Track the last confirmed response and saved tool outputs. A transport failure can leave the server ahead of the client. Preserve the transcript for explicit recovery without executing a completed handler again.

## Interfaces and Dependencies

Hard prerequisites are [EP-12](../plans/12-execute-registered-client-tools-across-message-turns.md), providing the accepted tool runner and its transcript. Place thread state and request encoding behind an opt-in API. Reuse the runner’s result correlation. The application selects thread retention; ordinary conversations continue to use full history. [Thread contract](https://platform.claude.com/docs/en/build-with-claude/message-threads)

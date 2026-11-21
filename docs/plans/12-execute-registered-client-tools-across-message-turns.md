---
id: 12
slug: execute-registered-client-tools-across-message-turns
title: "Execute registered client tools across message turns"
kind: exec-plan
created_at: 2026-11-21T03:23:04Z
master_plan: "docs/masterplans/4-run-client-tools-across-claude-conversation-turns.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:04Z
---

# Execute registered client tools across message turns

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

## Purpose / Big Picture

Run a conversation from client tool calls to the assistant’s final reply with application-supplied handlers.

## Progress

- [ ] Two registered handlers produce correlated tool results in one follow-up request.
- [ ] A bounded run reports terminal, interrupted and failed turns without repeating side effects.

## Surprises & Discoveries

## Decision Log

## Outcomes & Retrospective

## Context and Orientation

`src/Claude/Messages.hs` supplies `createMessage` and `continueMessage`. `src/Claude/Messages/Features.hs` distinguishes client calls from provider-side calls and represents `ToolResult`. Today applications perform the dispatch and continuation themselves.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) assigns HTTP cleanup and attempt ownership. The [assistant replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) preserves original provider objects and scopes continuation to the originating provider and model. The reviewed reference is TypeScript SDK tag `sdk-v1.12.0` (commit `3edf5eb`), `src/resources/beta/messages/messages.ts` in `mori://anthropics/anthropic-sdk-typescript` (artifact-level URI pending). [Pinned SDK source](https://github.com/anthropics/anthropic-sdk-typescript/blob/sdk-v1.12.0/src/resources/beta/messages/messages.ts)

## Plan of Work

Add `src/Claude/Tools.hs` with an explicit registry pairing each client tool declaration and handler. Decode arguments and encode results at that boundary. Build a unary runner which observes a full turn before dispatch, runs admitted client calls in block order and submits one result per original ID in a single user turn. Keep the original tools, container and model via the existing continuation policy. Return final response, turn count and enough completed history/results to diagnose a failed continuation. Define a positive turn budget and return on refusal, pause, truncation or exhaustion. Distinguish a handler-declared tool error from a thrown exception. Do not retry dispatch or execute server tools.

## Concrete Steps

Add `test/ToolsSpec.hs` to the test suite’s `other-modules` in `claude-hs.cabal` and call its `run` from `test/Main.hs`. Expose any new public module under the Cabal library’s `exposed-modules`. Use `test/Support/Server.hs` for network fixtures and synthetic credentials.

Run from the repository root in the locked development shell.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test claude-hs-test --test-show-details=direct
```

Both commands should exit successfully and Cabal should report the client test suite passed.

## Validation and Acceptance

Serve two client calls, a server call and signed history in one response. Assert which handlers ran, their order, the exact IDs on the next POST and terminal reply. Unknown tools, duplicate call IDs, malformed inputs and budget exhaustion must leave observable counts consistent. Simulate failure after a completed handler and cancellation during a handler. Demonstrate that the runner does not invoke it a second time.

## Idempotence and Recovery

A tool may produce an external effect before a later tool or provider call fails. Surface completed results and pending IDs so the application can reconcile effects before any manual retry. Propagate asynchronous exceptions.

## Interfaces and Dependencies

This plan can begin against the current library. The caller supplies the handlers and owns external side effects. Build the loop on a completed-turn function so a caller can adapt the completed streaming interface when available. Full-history unary execution can ship independently.

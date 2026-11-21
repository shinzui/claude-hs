---
id: 11
slug: return-the-assembled-message-from-a-live-stream
title: "Return the assembled message from a live stream"
kind: exec-plan
created_at: 2026-11-21T03:23:03Z
master_plan: "docs/masterplans/3-assemble-streamed-claude-responses-for-conversation-replay.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:03Z
---

# Return the assembled message from a live stream

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

## Purpose / Big Picture

Display incoming events immediately and obtain one final `MessageResponse` from the same HTTP request.

## Progress

- [ ] One request delivers an event before EOF and returns a replayable final message.
- [ ] Caller stop, stream failures and cancellation release the response without reporting a completed message.

## Surprises & Discoveries

## Decision Log

## Outcomes & Retrospective

## Context and Orientation

`src/Claude/Streaming.hs` scopes the callback to an open HTTP response. `Finished` and `Stopped` report why delivery ended. `src/Claude/Internal/Sse.hs` frames bytes and `src/Claude/Internal/Http.hs` closes the response.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) assigns HTTP cleanup and attempt ownership. The [assistant replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) preserves original provider objects and scopes continuation to the originating provider and model. The reviewed reference is TypeScript SDK tag `sdk-v1.12.0` (commit `3edf5eb`), `src/lib/MessageStream.ts` in `mori://anthropics/anthropic-sdk-typescript` (artifact-level URI pending). [Pinned SDK source](https://github.com/anthropics/anthropic-sdk-typescript/blob/sdk-v1.12.0/src/lib/MessageStream.ts)

## Plan of Work

Add an opt-in collecting entry point beside `streamMessage`. Fold each delivered event using the accepted accumulator, with state private to this call. Retain synchronous callbacks, request metadata and the ability to stop. Return a distinct caller-stopped outcome and a completed outcome containing the final message. Define the outcome when the callback stops on the terminal event consistently with existing stop precedence. Map assembly failure through a documented error path. Export final text through the existing `responseText` projection.

## Concrete Steps

Extend the existing `test/StreamingSpec.hs` cases invoked by `test/Main.hs`. Expose any new public module under the Cabal library’s `exposed-modules`. Use `test/Support/Server.hs` for network fixtures and synthetic credentials.

Run from the repository root in the locked development shell.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test claude-hs-test --test-show-details=direct
```

Both commands should exit successfully and Cabal should report the client test suite passed.

## Validation and Acceptance

Gate a loopback response after its first event until the callback signals receipt. Finish with a tool call and send its result via `continueMessage`. Compare that next POST with the unary equivalent. Repeat with immediate stop, truncated SSE, a provider error after partial output, a throwing callback and asynchronous cancellation. Verify cleanup and one provider request per attempt.

## Idempotence and Recovery

Start each call with fresh state. Cancellation or callback exceptions must unwind the existing HTTP bracket. Never resume an interrupted provider stream by issuing a second POST.

## Interfaces and Dependencies

Hard prerequisites are [EP-10](../plans/10-fold-message-events-into-a-complete-response.md), providing the accepted pure fold. Keep `streamMessage`, `streamMessageValue`, and standalone SSE consumers source-compatible. The collecting result is the input to structured output and optional streamed tool execution.

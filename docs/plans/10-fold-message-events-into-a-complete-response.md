---
id: 10
slug: fold-message-events-into-a-complete-response
title: "Fold message events into a complete response"
kind: exec-plan
created_at: 2026-11-21T03:23:03Z
master_plan: "docs/masterplans/3-assemble-streamed-claude-responses-for-conversation-replay.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:03Z
---

# Fold message events into a complete response

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

## Purpose / Big Picture

Reconstruct a complete assistant message from decoded server-sent events so callers can replay signed blocks and tool inputs exactly as they would after a unary response.

## Progress

- [ ] A pure event fold reproduces a captured unary message from a fragmented stream.
- [ ] Malformed or incomplete event sequences yield an assembly error with no final message.

## Surprises & Discoveries

## Decision Log

## Outcomes & Retrospective

## Context and Orientation

`src/Claude/Streaming.hs` exports `StreamEvent`, its original JSON and `applyUsageUpdate`. `src/Claude/Messages.hs` exposes `MessageResponse` and encodes it from `responseJSON`. `src/Claude/Messages/Features.hs` keeps each original block object.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) assigns HTTP cleanup and attempt ownership. The [assistant replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) preserves original provider objects and scopes continuation to the originating provider and model. The reviewed reference is TypeScript SDK tag `sdk-v1.12.0` (commit `3edf5eb`), `src/lib/MessageStream.ts` in `mori://anthropics/anthropic-sdk-typescript` (artifact-level URI pending). [Pinned SDK source](https://github.com/anthropics/anthropic-sdk-typescript/blob/sdk-v1.12.0/src/lib/MessageStream.ts)

## Plan of Work

Define empty, step and finish operations on an opaque accumulator. Start from `message_start`, track open blocks by numeric index and emit them in provider order. Append text and thinking fragments, append citations in arrival order and assign the provider signature verbatim. Buffer fragmented tool input JSON. Parse tool JSON once at block completion. Preserve block-start extension fields and untouched unknown blocks. Merge cumulative usage with `applyUsageUpdate`, apply stop and container updates, and synchronize the raw message object with the typed projection before reusing the unary decoder. Ignore pings. Report unsupported deltas that could change an assembled block rather than fabricating complete replay data. Finish only after a valid `message_stop` with all blocks closed.

## Concrete Steps

Extend the existing `test/StreamingSpec.hs` cases invoked by `test/Main.hs`. Expose any new public module under the Cabal library’s `exposed-modules`. Use `test/Support/Server.hs` for network fixtures and synthetic credentials.

Run from the repository root in the locked development shell.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test claude-hs-test --test-show-details=direct
```

Both commands should exit successfully and Cabal should report the client test suite passed.

## Validation and Acceptance

Feed an event list directly into the fold. Compare both `toJSON` of the final response and the assistant continuation with a unary fixture containing signed thinking, a tool call split inside a JSON string, citations and an unknown block with extra fields. Exercise explicit zero and omitted usage, mismatched indices, duplicate starts, invalid tool JSON, premature stop and EOF. Keep the low-level event decoder open to unknown tags.

## Idempotence and Recovery

The fold is pure. Replay the captured events into fresh state after a decoder change. Treat an interrupted stream as incomplete.

## Interfaces and Dependencies

This plan can begin against the current library. Expose the pure operations via `Claude.Streaming` without adding lifecycle state to the existing callback API. Use an internal module if necessary to avoid a module cycle. The stream wrapper in EP-11 will consume this interface.

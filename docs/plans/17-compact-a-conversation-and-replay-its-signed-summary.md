---
id: 17
slug: compact-a-conversation-and-replay-its-signed-summary
title: "Compact a conversation and replay its signed summary"
kind: exec-plan
created_at: 2026-11-21T03:23:04Z
master_plan: "docs/masterplans/6-complete-advanced-messages-controls-and-signed-compaction.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:04Z
---

# Compact a conversation and replay its signed summary

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

## Purpose / Big Picture

Request a signed summary and replace the conversation prefix with it on the next generation call.

## Progress

- [ ] A typed top-level compaction request returns an observable summary, stop reason and original signed evidence.
- [ ] Successful replay sends the summary first and drops the summarized history; failed compaction leaves the caller’s history available.

## Surprises & Discoveries

## Decision Log

## Outcomes & Retrospective

## Context and Orientation

`src/Claude/Messages/Features.hs` currently defines an edit named `Compaction` under `context_management`. `src/Claude/Messages.hs` filters unknown blocks in `continueMessage`, which ordinarily appends history. Explicit summarization is a distinct operation that replaces history.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) assigns HTTP cleanup and attempt ownership. The [assistant replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) preserves original provider objects and scopes continuation to the originating provider and model. The reviewed reference is TypeScript SDK tag `sdk-v1.12.0` (commit `3edf5eb`), `src/resources/beta/messages/messages.ts` in `mori://anthropics/anthropic-sdk-typescript` (artifact-level URI pending). [Pinned SDK source](https://github.com/anthropics/anthropic-sdk-typescript/blob/sdk-v1.12.0/src/resources/beta/messages/messages.ts)

## Plan of Work

Define a distinct request option or builder for top-level `compaction` with `type=summarize` and optional instructions. Select the compact-2026-09-04 beta for this operation. Use the beta contract for compatible fields, count projection and required headers. Reject the incompatible combination with `context_management` before dispatch. Decode a compaction stop and block with nullable content, encrypted content, signature and tool changes. Preserve the full block including future keys. A compaction_delta assigns its final content and, when present, encrypted_content. A null final content reports failed compaction. Provide an explicit history replacement helper which accepts a successful summary, carries the original configuration forward, removes one-shot compaction and sends the summary as the first assistant message followed by the new input. Leave the original request usable when compaction fails.

## Concrete Steps

Extend the existing `test/FeaturesSpec.hs` cases invoked by `test/Main.hs`. Expose any new public module under the Cabal library’s `exposed-modules`. Use `test/Support/Server.hs` for network fixtures and synthetic credentials.

Run from the repository root in the locked development shell.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test claude-hs-test --test-show-details=direct
```

Both commands should exit successfully and Cabal should report the client test suite passed.

## Validation and Acceptance

Capture an original conversation with earlier tool edits. Return a single signed compaction block and assert the exact next generation POST replays its signature, encrypted bytes, tool changes and extra fields, omits the old turns, and omits the compaction request flag. Test null summary, malformed summary and conflicting controls. Cover the typed stream’s compaction compaction_delta content and encrypted_content plus signed block evidence and compare assembled to unary once the accumulator is available. Keep a regression for the existing triggered edit.

## Idempotence and Recovery

Construct a replacement conversation only after validating the returned block. Keep the full original history on refusal, missing summary, corrupt data or interrupted streaming.

## Interfaces and Dependencies

Hard prerequisites are [EP-10](../plans/10-fold-message-events-into-a-complete-response.md), providing the accepted pure stream fold. Give history replacement its own operation in `Claude.Messages`; an ordinary continuation appends. Coordinate new block delta constructors in `Claude.Streaming` with its public fold, retaining raw event evidence. Use fixtures with synthetic signatures only.

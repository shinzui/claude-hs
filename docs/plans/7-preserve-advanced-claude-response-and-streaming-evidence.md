---
id: 7
slug: preserve-advanced-claude-response-and-streaming-evidence
title: "Preserve advanced Claude response and streaming evidence"
kind: exec-plan
created_at: 2026-11-20T21:15:41Z
master_plan: "docs/masterplans/2-reach-mercury-claude-feature-parity-and-migrate-baikai.md"
provenance:
  created_by:
    model: "gpt-6.2-sol"
    harness: "codex-cli"
    at: 2026-11-20T21:15:41Z
---

# Preserve advanced Claude response and streaming evidence

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

## Purpose / Big Picture

Applications can inspect structured refusal details, provider billing evidence and advanced tool state when a request completes or while it streams. The same information is available to a Baikai migration without decoding Mercury events. Providers' signed and opaque content remains suitable for a subsequent assistant turn.

## Progress

- [ ] A Baikai-shaped fixture projects refusal details, context-window stop, reasoning token usage, service tier and speed from the candidate response and SSE observations.
- [ ] The complete, stream and batch fixtures decode all advanced response variants from the Mercury baseline and replay the supported opaque blocks.

## Surprises & Discoveries

## Decision Log

## Outcomes & Retrospective

## Context and Orientation

`src/Claude/Messages.hs` currently decodes `MessageResponse`, `StopReason` and `Usage`. It keeps core counts and some cache and server-tool information but drops envelope-level fields such as `stop_details`, `container` and `usage.output_tokens_details`. `src/Claude/Streaming.hs` exposes each event's original JSON in `eventJSON`, while its typed message delta and usage update leave out those observations. `src/Claude/Messages/Features.hs` uses `UnknownBlock` and the original block JSON for unknown provider variants. Successful batches use the same Messages decoder. [HTTP boundary](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) and [content replay](../adr/0003-preserve-provider-content-for-assistant-replay.md) define the ownership rules.

Compare against the released `mori://MercuryTechnologies/claude/packages/claude` 1.5.0 `Claude.V1.Messages` and `Claude.V1.Error`. The trial for `mori://shinzui/baikai/packages/baikai-claude` still projects original JSON into Mercury event types. Inspect the current Baikai assembler's `Message_Start` and `Message_Delta` branches and the public fixtures for refusals, pricing and cumulatively reported usage. [Mercury 1.5.0](https://hackage-content.haskell.org/package/claude-1.5.0)

## Plan of Work

Begin with one refusal and one cumulative usage transcript. Use the candidate types to derive the exact Baikai classification and usage without importing Mercury in the new projection. Add typed context-window exhaustion and structured stop details for refusal, with optional observations and an extensible unknown variant if the provider adds categories. Cover both synchronous and SSE stop details. Model reasoning token breakdown, inference geography, service tier, speed and iteration usage, including fallback iterations. Add typed server-tool counts alongside retained extensions. Distinguish missing stream fields from reported zero. Carry the same exact provider metadata into batch success decoding. Add typed error categories covering Mercury's error enum while retaining unknown tags and classifying transport separately.

Extend block and envelope observations for tool caller, tool-search results and references, code-execution results and errors, container IDs and expiry, model fallback markers and provider evidence supporting continuation. A container identifies the provider's execution state and can be supplied on a later request. Add decode coverage for reported types. Preserve opaque fields in provider JSON and check valid replay, including those fields the client cannot interpret yet. Make supported outgoing-history and response data available to callers as JSON without dropping unknown content; reuse the shared conversion rather than copying tool payloads. Integrate with the request plan through the already accepted `ReplayBlock` mechanics and verify the interaction at the parent gate. [Streaming](https://platform.claude.com/docs/en/build-with-claude/streaming), [refusals and fallback](https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback)

## Concrete Steps

From the `claude-hs` repository root, read the released comparison and run the locked-shell tests with a credential-free fixture server.

```bash
mori path mori://MercuryTechnologies/claude/packages/claude
mori path mori://shinzui/baikai/packages/baikai-claude
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c env -u ANTHROPIC_API_KEY cabal test all --test-show-details=direct
```

Record the incoming capability, fixture and typed or raw representation in [Messages coverage](../messages-coverage.md). Use versioned wire docs and synthetic opaque fields.

## Validation and Acceptance

Exercise the same provider observations through public Messages, SSE and a successful batch item. Preserve refusal category and explanation. Distinguish an exhausted model context from a refusal. Capture thinking token counts, speed, service tier, tool usage and final iteration data. Apply cumulative deltas and verify that absent counters retain earlier observations and zero is preserved. Check known invalid variants produce a typed decode failure and new optional fields survive raw replay. Check tool search references, programmatic tool caller values, code-execution error/success payloads, container reuse evidence and fallback identity. Keep already accepted citations, unknown events, signed thinking and pre-EOF cancellation green.

## Idempotence and Recovery

Use captured or synthetic transcripts and fixture keys. Run the producer projection in a disposable checkout and compare against the first trial. Re-run the loopback fixtures freely.

## Interfaces and Dependencies

Own incoming codecs in `Claude.Messages`, `Claude.Messages.Features` and `Claude.Streaming`. Batch results consume `MessageResponse`. The Baikai adopter consumes the typed observations and original opaque history. No prerequisite child plan.

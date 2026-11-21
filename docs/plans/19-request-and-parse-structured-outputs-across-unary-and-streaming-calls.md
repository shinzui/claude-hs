---
id: 19
slug: request-and-parse-structured-outputs-across-unary-and-streaming-calls
title: "Request and parse structured outputs across unary and streaming calls"
kind: exec-plan
created_at: 2026-11-21T03:23:04Z
master_plan: "docs/masterplans/7-parse-structured-claude-outputs-into-haskell-values.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:04Z
---

# Request and parse structured outputs across unary and streaming calls

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

## Purpose / Big Picture

Request a schema and receive a typed Haskell result in one call, including when the caller also displays a live stream.

## Progress

- [ ] Unary structured generation installs the schema, preserves effort and returns typed output plus response metadata.
- [ ] Streaming structured generation delivers events immediately and parses only a completed assembled response.

## Surprises & Discoveries

## Decision Log

## Outcomes & Retrospective

## Context and Orientation

`src/Claude/Messages.hs` supplies `createMessage`; `MessageFeatures.outputConfig` holds schema and effort. The pure structured parser and opt-in stream collector come from the prerequisites. Both produce or consume the same `MessageResponse`.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) assigns HTTP cleanup and attempt ownership. The [assistant replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) preserves original provider objects and scopes continuation to the originating provider and model. The reviewed reference is TypeScript SDK tag `sdk-v1.12.0` (commit `3edf5eb`), `src/resources/messages/messages.ts` in `mori://anthropics/anthropic-sdk-typescript` (artifact-level URI pending). [Pinned SDK source](https://github.com/anthropics/anthropic-sdk-typescript/blob/sdk-v1.12.0/src/resources/messages/messages.ts)

## Plan of Work

Add typed unary and streaming entry points in `src/Claude/Structured.hs` taking the paired schema/decoder and existing request/options. Install the JSON Schema format, preserve effort and other controls, accept an equivalent preconfigured format and return a clear configuration error for conflicting formats. Call the normal validated endpoints once. On completion retain metadata, original message and parse outcome. Preserve stopped streams, errors and asynchronous cancellation. Show a short record example and the refusal branch in `docs/messages-coverage.md`.

## Concrete Steps

Extend `test/StructuredSpec.hs`, registered by the prerequisite, through its existing `run` function. Expose any new public module under the Cabal library’s `exposed-modules`. Use `test/Support/Server.hs` for network fixtures and synthetic credentials.

Run from the repository root in the locked development shell.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test claude-hs-test --test-show-details=direct
```

Both commands should exit successfully and Cabal should report the client test suite passed.

## Validation and Acceptance

Capture a unary request with effort and schema, then emit an equivalent SSE response with JSON split in the middle of a string. Observe the callback before completion and compare parsed values, usage and request IDs from the same respective responses. Test structured refusal, max tokens, invalid output, early stop, provider error and conflicting schema. Verify early stop never yields a parsed success and schema conflict sends zero requests.

## Idempotence and Recovery

Return the original completed message on a parse failure so callers can inspect or reparse it without a second provider request. A cancelled stream cannot produce a final structured value.

## Interfaces and Dependencies

Hard prerequisites are [EP-18](../plans/18-decode-schema-constrained-message-responses.md), [EP-11](../plans/11-return-the-assembled-message-from-a-live-stream.md), providing the accepted pure structured decoder and live stream collector. The pure decoder owns parsing and the stream collector owns event assembly. Both endpoint helpers call the same schema-installation function so their wire requests differ only in streaming controls.

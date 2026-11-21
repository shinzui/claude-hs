---
id: 18
slug: decode-schema-constrained-message-responses
title: "Decode schema constrained message responses"
kind: exec-plan
created_at: 2026-11-21T03:23:04Z
master_plan: "docs/masterplans/7-parse-structured-claude-outputs-into-haskell-values.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:04Z
---

# Decode schema constrained message responses

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

## Purpose / Big Picture

Decode structured assistant text into an application-selected Haskell type while retaining the original response, stop reason, and a specific failure outcome.

## Progress

- [ ] A schema and decoder pair returns typed values from completed text blocks.
- [ ] Refusal, truncation, missing text, invalid JSON and type mismatches are distinguishable to callers.

## Surprises & Discoveries

## Decision Log

## Outcomes & Retrospective

## Context and Orientation

`src/Claude/Messages.hs` exposes `responseText` which concatenates text and `MessageResponse` with ordered blocks. `src/Claude/Messages/Features.hs` defines `OutputConfig` with independent format and effort. Use the existing Aeson dependency for JSON decoding.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) assigns HTTP cleanup and attempt ownership. The [assistant replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) preserves original provider objects and scopes continuation to the originating provider and model. The reviewed reference is TypeScript SDK tag `sdk-v1.12.0` (commit `3edf5eb`), `src/lib/parser.ts` in `mori://anthropics/anthropic-sdk-typescript` (artifact-level URI pending). [Pinned SDK source](https://github.com/anthropics/anthropic-sdk-typescript/blob/sdk-v1.12.0/src/lib/parser.ts)

## Plan of Work

Introduce `src/Claude/Structured.hs`. Pair the provider's JSON Schema object with a decoder for one JSON value, including a convenience constructor using `FromJSON`. Define a pure parse operation on an already decoded `MessageResponse`. Inspect stop reason before claiming success. For a completed reply parse each text block as a separate JSON document, retain its block index and expose the first parsed value as the primary result. Keep nontext blocks in the original message. Give truncated/refused or unfinished turns, no text, malformed JSON and application decode errors distinct outcomes. Document that an Aeson decoder enforces the application's type contract; callers can supply stricter validation.

## Concrete Steps

Add `test/StructuredSpec.hs` to the test suite’s `other-modules` in `claude-hs.cabal` and call its `run` from `test/Main.hs`. Expose any new public module under the Cabal library’s `exposed-modules`. Use `test/Support/Server.hs` for network fixtures and synthetic credentials.

Run from the repository root in the locked development shell.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test claude-hs-test --test-show-details=direct
```

Both commands should exit successfully and Cabal should report the client test suite passed.

## Validation and Acceptance

Exercise a response with two independently valid text documents separated by a thinking block. Check block indices, first value and original signed evidence. Include a truncated response containing syntactically valid JSON, a refusal with text, an empty response, malformed JSON, and valid JSON with the wrong field type. Show an application record decoded from a schema and `FromJSON` instance.

## Idempotence and Recovery

The decoder has no side effects. Reparse the same response with a different application decoder without generating another message.

## Interfaces and Dependencies

This plan can begin against the current library. Keep parsing independent of HTTP so saved responses and successful batch items can share it. Use existing `MessageResponse` and `OutputConfig` without adding a schema inference dependency.

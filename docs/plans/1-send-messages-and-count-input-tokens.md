---
id: 1
slug: send-messages-and-count-input-tokens
title: "Send messages and count input tokens"
kind: exec-plan
created_at: 2026-11-20T19:36:14Z
master_plan: "docs/masterplans/1-build-a-haskell-client-for-the-claude-messages-api.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-20T19:36:14Z
---

# Send messages and count input tokens

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

A Haskell caller can send a conversation to Claude and estimate its input tokens using one configured client. A test caller exercises the public API against a local HTTP server, including an API failure.

## Progress

- [ ] A typed text conversation completes over HTTP and preserves response metadata and failures.
- [ ] Token counting and multi-turn image/text fixtures pass through the same public client.

## Surprises & Discoveries



## Decision Log



## Outcomes & Retrospective



## Context and Orientation

At planning time this repository contains planning skills and no Cabal package or local ADRs. The direct consumer is `mori://shinzui/baikai/packages/baikai-claude`, which imports Mercury request types and has its own SSE transport and provider policy. `mori://shinzui/shikumi/packages/shikumi` uses that adapter. `mori://shinzui/shikigami/packages/shikigami-core` relies on governed provider attempts through its program runtime. `mori://shinzui/shikumi/okf/adrs/concepts/ADR-11` requires structured failures for downstream retry decisions. `mori://shinzui/shikumi/okf/adrs/concepts/ADR-14` distinguishes schema enforcement from tool calling. The historical API surface is available at `mori://MercuryTechnologies/claude/packages/claude`. The old default header was 2023-06-01. This package targets the direct API version 2026-10-21. [Version migration guide](https://platform.claude.com/docs/en/api/migration-2026-10-21).

## Plan of Work

First create `claude-hs.cabal`, `cabal.project`, public modules `src/Claude/Client.hs` and `src/Claude/Messages.hs`, and private `src/Claude/Internal/Http.hs`. Use one Cabal common stanza with GHC2024, DeriveAnyClass, DuplicateRecordFields, OverloadedLabels and OverloadedStrings for all components. Follow `mori://shinzui/haskell-jitsurei/docs/core-standards` and `mori://shinzui/haskell-jitsurei/docs/core-record-patterns`. Use strict record fields, explicit deriving strategies, postpositive qualified imports and generic-lens labels for access and updates. Use explicit wire keys wherever the protocol differs from Haskell naming. Look up each chosen package with Mori, read its source, then check Hackage and upstream tags before setting bounds. Use the same compiler in development and the project's automated build/test job.

Implement a reusable, opaque client with an explicit key, endpoint, timeout and reusable connection manager. Default to https://api.anthropic.com. Permit per-request beta and provider metadata headers so Baikai can pass session affinity. Define a collision policy for library-owned authentication, version and framing headers. Scope credentials to the configured origin. Redact secrets in rendered errors. Disable automatic retries of submitted requests including manager retries on reused connections. Preserve caller cancellation and callback exceptions. Put status checks, request IDs, parsing of the API error envelope, and scoped access to the response body in the internal HTTP module. A single local text roundtrip is the first proof.

Next model user/assistant history, optional system text, text and image input, message ID, ordered response blocks, stop reason and usage. Allow a new model ID as text and retain unknown tagged response blocks as JSON. Use required arguments or validated constructors for model, nonempty conversation and positive output limit. Build a separate count request from shared input fields and verify its endpoint-specific body. Add a small compilable usage example and transport setup instructions in README.md. [Create a Message](https://platform.claude.com/docs/en/api/messages/create) and [Count tokens](https://platform.claude.com/docs/en/api/messages/count_tokens).

## Concrete Steps

From the repository root, with GHC 9.12 or newer and cabal-install available, run the following after each milestone. The library must build and the local test suite must report PASS with no Anthropic key in the environment.

```bash
cabal build all
cabal test all --test-show-details=direct
```

## Validation and Acceptance

Use a loopback server in `test/Support/Server.hs` and register `test/MessagesSpec.hs` from `test/Main.hs`. Assert method, path, API key sentinel, exact version and omitted optional fields. POST /v1/messages must return the fixture's text, model, stop reason and input/output counts. For POST /v1/messages/count_tokens return 17 input tokens, inspect the supplied history and assert the output limit is absent. Cover a non-JSON 502, a 429 with request ID and Retry-After, invalid JSON on HTTP 200, an unknown block and a disconnected POST. Observe one attempt, differentiated errors, and secret-free diagnostics. The complete request fixture omits temperature, top_p and top_k under the selected version. Compile a narrow Baikai-style request mapping with the public package, including provider session headers, before extending endpoint coverage. Check the captured request and header values.

## Idempotence and Recovery

Use ephemeral loopback ports and bracket server lifetime per test. A failed fixture run is safe to repeat. Leave retry timing and the decision to repeat a billable call to the downstream runtime.

## Interfaces and Dependencies

Expose createMessage and countTokens as Client plus typed request to IO (Either ClientError result). Keep successful response metadata available, including request ID. Distinguish transport, API status/envelope and protocol decode errors. Model a refusal stop separately from HTTP failure. The internal runner takes a method, endpoint path, request options/body and a scoped reader callback. Keep Aeson codecs shared between Messages, streaming and batches. No prerequisite child.

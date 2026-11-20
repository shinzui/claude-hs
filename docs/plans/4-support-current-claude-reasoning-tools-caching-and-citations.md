---
id: 4
slug: support-current-claude-reasoning-tools-caching-and-citations
title: "Support current Claude reasoning, tools, caching and citations"
kind: exec-plan
created_at: 2026-11-20T19:36:44Z
master_plan: "docs/masterplans/1-build-a-haskell-client-for-the-claude-messages-api.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-20T19:36:44Z
  revisions:
    - model: "gpt-6.2-astra"
      harness: "codex-cli"
      at: 2026-11-20T20:25:29Z
      mode: "update"
      note: "Use the Seihou-generated Nix development shell for client builds and tests."
    - model: "gpt-6.2-sol"
      harness: "codex-cli"
      at: 2026-11-20T20:35:46Z
      mode: "implement"
      note: "Extend the shared Messages codecs and verify feature replay over HTTP."
---

# Support current Claude reasoning, tools, caching and citations

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

A caller can request schema-constrained output, use signed adaptive thinking across a tool turn, see cache usage and recover document and web citations. These behaviors are exercised at the public Messages boundary.

## Progress

- [x] 2026-11-20. The loopback suite verified schema-only and tool-only requests, schema with effort, the count projection, and two consecutive tool rounds with empty, visible and redacted thinking.
- [x] 2026-11-20. The fixtures verified automatic and explicit cache controls, both cache counters, and original document and web citation evidence on replay.

## Surprises & Discoveries



## Decision Log



## Outcomes & Retrospective

The library and example built with GHC 9.12.4. The loopback suite passed with the key unset, including a refusal, a malformed known thinking block and an unknown server result. The [content replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) records the shared codec and scope. [Messages coverage](../messages-coverage.md) records feature restrictions and the migration audit for removed sampling fields.



## Context and Orientation

Begin after `docs/plans/1-send-messages-and-count-input-tokens.md` is complete. It supplies a buildable package, the public `Claude.Messages` types, a reusable `Claude.Client`, typed `ClientError`, a bracketed internal HTTP response reader and a loopback test server. `mori://shinzui/shikumi/okf/adrs/concepts/ADR-11` requires structured failures for downstream retry decisions. `mori://shinzui/shikumi/okf/adrs/concepts/ADR-14` distinguishes schema enforcement from tool calling. For the following filesystem ADRs the artifact-level URI is pending. `mori://shinzui/baikai` plus `docs/adr/0010-a-stream-consumer-that-stops-owns-cancelling-the-producer.md` assigns cancellation to the stream consumer. `mori://shinzui/baikai` plus `docs/adr/0019-reasoning-continuation-is-scoped-to-its-provider-and-model.md` requires faithful replay within the same model and provider. `mori://shinzui/shikigami` plus `docs/adr/0043-decision-provider-wrappers-own-actual-attempt-boundaries.md` assigns attempt accounting to the calling runtime. The corpus already implements some modern request fields. Its text response decoder keeps text alone and loses citations. Use that concrete case as a regression. Follow `mori://shinzui/haskell-jitsurei/docs/core-standards` and `mori://shinzui/haskell-jitsurei/docs/core-record-patterns`. Use strict record fields, explicit deriving strategies, postpositive qualified imports and generic-lens labels for access and updates. Use explicit wire keys wherever the protocol differs from Haskell naming.

## Plan of Work

Extend `src/Claude/Messages.hs` using `src/Claude/Messages/Features.hs` for feature-specific types. Add typed output_config.format for a caller-supplied JSON schema, independent effort, adaptive thinking and display, tool definitions with input_schema and strict, tool choice, tool_use and tool_result blocks. Preserve the full provider-issued reasoning block, including opaque data and signature, for a subsequent assistant turn. Keep tool execution in the caller. Expose structured output text for decoding into a caller type and retain stop reason so refusal or truncation is observable. [Structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs), [thinking](https://platform.claude.com/docs/en/build-with-claude/thinking) and [strict tools](https://platform.claude.com/docs/en/agents-and-tools/tool-use/strict-tool-use).

Add automatic and explicit cache breakpoints, optional supported TTL, and cache creation/read usage. Add plain-text document inputs with citations enabled and typed source locations on returned text. Cover a versioned server-run web search, including its tool use, result, error variant, cited text, and opaque search evidence required on replay. Support versioned tool definitions and unknown tagged results through an explicit raw JSON case. Distinguish fields a caller may send from fields received. Keep schema output and citations as separate examples because enabling both is rejected. Record supported operations, model restrictions, beta headers and evidence in `docs/messages-coverage.md`. Date the reference samples and describe how to refresh a fixture when the API changes. [Prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching), [citations](https://platform.claude.com/docs/en/build-with-claude/citations) and [server web search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool).

Inventory the fields actually emitted by the Baikai Claude provider before freezing constructors. Include request-local versioned extensions for options such as speed plus its beta header. Preserve manual budgets, disabled thinking, absent effort, multiple cache TTLs, and signed empty or redacted blocks wherever supported by the selected contract. Document version-dependent legacy fields explicitly. In particular, a caller targeting 2026-10-21 must be able to detect incompatible sampling settings during migration.

## Concrete Steps

From the repository root, build and test each client milestone in the locked development shell provided by EP-1. See the [tooling ADR](../adr/0001-bootstrap-haskell-tooling-with-seihou.md). The library must build and the local test suite must report PASS with no Anthropic key in the environment.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test all --test-show-details=direct
```

## Validation and Acceptance

In `test/FeaturesSpec.hs`, inspect actual JSON captured from the public client. Assert schema and effort coexist under output_config, a strict tool is nested under tools, and the next turn carries the original signed block, tool ID and result. Check schema-only and tool-only calls independently. Decode a refusal with its stop reason. Verify a cached system block and both cache token counters. Decode a text block containing a character-range citation and another containing a web search URL and encrypted index. Check the location and opaque fields survive reading and valid assistant-history replay. Send an unknown result block through the same path. Test malformed required fields in a known variant as a typed decode error. Include an example schema request in countTokens using the endpoint's documented projection. Add Baikai-derived fixtures for two consecutive tool rounds with signed empty, visible and redacted thinking, and a tool-level cache breakpoint. Preserve source fields needed for replay even when callers do not inspect them.

## Idempotence and Recovery

Use synthetic signatures, keys and citation indices. Refresh fixtures deliberately against dated upstream examples and compare semantic JSON. Replaying the two-turn loopback test is free of external side effects.

## Interfaces and Dependencies

This child owns the feature-specific request options, content block variants, citation structures and lossless continuation conversion within the Messages interface. The base owns the HTTP runner and generic message envelope. Use a shared block codec across responses, stream starts, and batch successes. Keep transport-specific beta tokens explicit.

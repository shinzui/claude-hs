---
id: 1
slug: build-a-haskell-client-for-the-claude-messages-api
title: "Build a Haskell client for the Claude Messages API"
kind: master-plan
created_at: 2026-11-20T19:35:56Z
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-20T19:35:56Z
  revisions:
    - model: "gpt-6.2-astra"
      harness: "codex-cli"
      at: 2026-11-20T20:25:29Z
      mode: "update"
      note: "Use the Seihou-generated Nix development shell for client builds and tests."
    - model: "gpt-6.2-sol"
      harness: "codex-cli"
      at: 2026-11-20T20:29:05Z
      mode: "implement"
      note: "Implement the client and verify plan acceptance against the locked toolchain."
---

# Build a Haskell client for the Claude Messages API

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Vision & Scope

Build a Cabal library, provisionally named `claude-hs`, for applications calling Anthropic directly. First-release workflows cover synchronous and streaming Messages, input token counts, and asynchronous batches. The priority is a working path for structured output, adaptive thinking, client tools, prompt caching, citations and server tools. A versioned web search tool is the first typed server-tool workflow. Additional tools can travel as versioned JSON. Bedrock, Vertex, administration, agent orchestration and source compatibility with Mercury are outside this release.

The direct consumer is `mori://shinzui/baikai/packages/baikai-claude`, which imports Mercury request types and has its own SSE transport and provider policy. `mori://shinzui/shikumi/packages/shikumi` uses that adapter. `mori://shinzui/shikigami/packages/shikigami-core` relies on governed provider attempts through its program runtime. Completion includes testing a candidate at the Baikai provider boundary and checking how its results reach the other two consumers. Production downstream migrations are separate changes.

## Decomposition Strategy

Start with one real message call to establish authentication, errors, codecs and test transport. The modern feature set needs its own workstream because both response replay and stream decoding depend on preserving content. Batches have a separate lifecycle and line format. Packaging, examples and tests ship with their owning behavior. The earlier library is comparison material. Its text decoder drops citations even though its request model already covers adaptive thinking and structured output. [Corpus package](mori://MercuryTechnologies/claude/packages/claude).

EP-1 bootstraps the tooling under the [tooling ADR](../adr/0001-bootstrap-haskell-tooling-with-seihou.md). `mori://shinzui/shikumi/okf/adrs/concepts/ADR-11` requires structured failures for downstream retry decisions. `mori://shinzui/shikumi/okf/adrs/concepts/ADR-14` distinguishes schema enforcement from tool calling. For the following filesystem ADRs the artifact-level URI is pending. `mori://shinzui/baikai` plus `docs/adr/0010-a-stream-consumer-that-stops-owns-cancelling-the-producer.md` assigns cancellation to the stream consumer. `mori://shinzui/baikai` plus `docs/adr/0019-reasoning-continuation-is-scoped-to-its-provider-and-model.md` requires faithful replay within the same model and provider. `mori://shinzui/shikigami` plus `docs/adr/0043-decision-provider-wrappers-own-actual-attempt-boundaries.md` assigns attempt accounting to the calling runtime. Follow `mori://shinzui/haskell-jitsurei/docs/core-standards` and `mori://shinzui/haskell-jitsurei/docs/core-record-patterns`. Use strict record fields, explicit deriving strategies, postpositive qualified imports and generic-lens labels for access and updates. Use explicit wire keys wherever the protocol differs from Haskell naming.

## Exec-Plan Registry

| # | Title | Path | Hard deps | Soft deps | Status |
|---|---|---|---|---|---|
| EP-1 | Send messages and count input tokens | [1-send-messages-and-count-input-tokens.md](../plans/1-send-messages-and-count-input-tokens.md) | None | None | In Progress |
| EP-2 | Stream message events as they arrive | [2-stream-message-events-as-they-arrive.md](../plans/2-stream-message-events-as-they-arrive.md) | EP-1, EP-4 | None | Not Started |
| EP-3 | Submit message batches and consume their results | [3-submit-message-batches-and-consume-their-results.md](../plans/3-submit-message-batches-and-consume-their-results.md) | EP-1 | None | Not Started |
| EP-4 | Support current Claude reasoning, tools, caching and citations | [4-support-current-claude-reasoning-tools-caching-and-citations.md](../plans/4-support-current-claude-reasoning-tools-caching-and-citations.md) | EP-1 | None | Not Started |
| EP-5 | Verify the client through Baikai, Shikumi and Shikigami | [5-verify-the-client-through-baikai-shikumi-and-shikigami.md](../plans/5-verify-the-client-through-baikai-shikumi-and-shikigami.md) | EP-2, EP-4 | None | Not Started |

## Dependency Graph

Start with EP-1, then prioritize EP-4. EP-3 can proceed concurrently with EP-4 once EP-1 is complete. EP-2 uses the accepted transport and feature codecs from both EP-1 and EP-4. EP-5 starts when EP-2 and EP-4 are complete and owns the consumer proof. EP-3 has no dependency on the stream parser. Reconcile batch and feature coverage with an enriched request in the final gate.

## Integration Points

EP-1 owns `Claude.Client`, the scoped response reader, errors, request options and the Messages envelope. EP-4 owns feature fields, content variants and continuation conversion within that envelope. EP-2 consumes those codecs for block starts and owns event framing. EP-3 embeds the Messages encoder and response decoder in batch items. EP-1 owns the Seihou-generated flake and lockfile used to build and test the client throughout the initiative. EP-1 owns the layout of `claude-hs.cabal`, README.md, `test/Main.hs` and the loopback harness. Later children register their own modules and fixtures there. Each begins with one public HTTP roundtrip. Record durable choices on error ownership, response lifetime and opaque content replay in local ADRs as those interfaces are implemented.

At the first working call, compile a minimal Baikai request mapping against the candidate and retain its captured request as an early consumer test. After EP-4 and EP-2, exercise the real provider in disposable local checkouts with a Cabal project selecting the candidate and a trial Baikai HTTP adapter. Capture the checkout revisions and resolved package plan. Compare the public complete and stream paths against the same scripted server. Run the Baikai provider suite for schema and tool-choice independence, signed empty/redacted reasoning across turns, cache usage, request IDs, errors and cancellation. Carry forward existing supported behavior or identify a documented version conflict with a tested migration path. Keep CLI subscriptions and host/model-specific policy owned by Baikai.

Use that same candidate adapter in the Shikumi and Shikigami checks. Drive a schema-constrained Shikumi prediction and a failing provider attempt through its error mapping. Through Shikigami's governed program runtime, count the wire requests and recorded attempts on success, terminal failure and cancellation. Assert exactly one accounted attempt per dispatch, preserved correlation/usage where provided, and no hidden retries. Record fixture names, commands, package revisions and outcomes here. A run using the old adapter or a stub above the provider cannot close this gate. Changes to the three production repositories require their own adoption work.

## Progress

EP-1 is in progress with the Seihou bootstrap applied. The consumer checks and the enriched batch fixture remain open.

## Surprises & Discoveries



## Decision Log

2026-11-20 — Target Anthropic’s 2026-10-21 Messages wire contract. Its removal of three sampling parameters makes direct reuse of the Mercury request record unsafe. Use dated official examples for wire behavior, the local corpus for migration evidence and downstream provider fixtures for compatibility. [Anthropic migration guide](https://platform.claude.com/docs/en/api/migration-2026-10-21).

2026-11-20 — Bootstrap the shared Haskell toolchain in EP-1 with the Seihou `nix-haskell-flake` template so developers and CI can build the client with the same compiler and Cabal environment.

## Outcomes & Retrospective

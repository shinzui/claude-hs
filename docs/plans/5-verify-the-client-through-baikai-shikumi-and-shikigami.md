---
id: 5
slug: verify-the-client-through-baikai-shikumi-and-shikigami
title: "Verify the client through Baikai, Shikumi and Shikigami"
kind: exec-plan
created_at: 2026-11-20T19:40:21Z
master_plan: "docs/masterplans/1-build-a-haskell-client-for-the-claude-messages-api.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-20T19:40:21Z
  revisions:
    - model: "gpt-6.2-sol"
      harness: "codex-cli"
      at: 2026-11-20T20:47:53Z
      mode: "implement"
      note: "Build and exercise the candidate driver in the downstream cohort."
---

# Verify the client through Baikai, Shikumi and Shikigami

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

Prove that a caller can substitute the new library in the actual Baikai Claude HTTP adapter and use the resulting provider in both downstream runtimes. Produce reproducible compatibility evidence and a trial adapter patch before proposing adoption.

## Progress

- [x] 2026-11-20. The patched Baikai suite passed 475 tests, including complete and stream comparison, two signed tool rounds and socket cancellation through the actual HTTP driver.
- [x] 2026-11-20. Shikumi passed 301 tests and Shikigami passed 820. Reapplying the patches in fresh checkouts reproduced all three suites and the local dependency selection.

## Surprises & Discoveries

The existing provider's timeout fixture sends an empty conversation under its older wire version. The bridge allows that legacy shape and keeps the nonempty requirement for the current version. Baikai also exposes a manager-injection helper used by a redirect fixture. The trial changes the live driver at the provider boundary and retains that helper.

The HTTP-date Retry-After path needs the response Date. The shared client now preserves it and provides a bounded, redacted error excerpt for the provider's status and overflow classifier.

Shikigami's full test suite hit fixture deadlines with several Tasty workers. See [FRIC-2](../friction-log/2-concurrent-shikigami-fixture-deadlines-expire-during-the-consumer-trial.md) for the serial test command.



## Decision Log

2026-11-20. Retain the trial provider's versioned request mapper and assembler. Replace its live HTTP driver with the candidate, translate errors and response correlation at the boundary, and project the candidate's validated events into the provider's current event types. This isolates a transport migration and preserves the request configuration digest.



## Outcomes & Retrospective

The trial [runbook](../../integration/consumers/README.md) records checkout revisions, the local Cabal dependency selection and the test commands. The Shikumi fixture decoded native schema output without adding tool choice and retained HTTP 429 status, category and Retry-After. The governed Shikigami fixture observed one dispatch and one recorded attempt in each scenario. It retained provider correlation and usage on success, correlated terminal failure, and recorded an unknown terminal on cancellation. The cancellation fixtures verified socket release after the consumer reached its blocked read. Three further focused runs passed.

FRIC-2 was accepted with serial Tasty scheduling. The [HTTP boundary ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) and [replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) record the durable transport and compatibility behavior.



## Context and Orientation

The direct consumer is `mori://shinzui/baikai/packages/baikai-claude`, which imports Mercury request types and has its own SSE transport and provider policy. `mori://shinzui/shikumi/packages/shikumi` uses that adapter. `mori://shinzui/shikigami/packages/shikigami-core` relies on governed provider attempts through its program runtime. `mori://shinzui/shikumi/okf/adrs/concepts/ADR-11` requires structured failures for downstream retry decisions. `mori://shinzui/shikumi/okf/adrs/concepts/ADR-14` distinguishes schema enforcement from tool calling. For the following filesystem ADRs the artifact-level URI is pending. `mori://shinzui/baikai` plus `docs/adr/0010-a-stream-consumer-that-stops-owns-cancelling-the-producer.md` assigns cancellation to the stream consumer. `mori://shinzui/baikai` plus `docs/adr/0019-reasoning-continuation-is-scoped-to-its-provider-and-model.md` requires faithful replay within the same model and provider. `mori://shinzui/shikigami` plus `docs/adr/0043-decision-provider-wrappers-own-actual-attempt-boundaries.md` assigns attempt accounting to the calling runtime. This repository had no local ADRs at plan creation. Use the Mori package records to locate the current source checkouts. The Baikai package's shape, transport, thinking, evidence, mid-stream and lifecycle suites describe its current public guarantees.

## Plan of Work

Prepare disposable clean checkouts of the consumer revisions used together by the current Shikigami workspace. In a temporary Cabal project select local package directories for the new client, the matching Baikai cohort, Shikumi and the Shikigami runtime. Preserve the original projects' constraints and other local dependencies as needed. In the trial Baikai package port the actual Messages request mapping, response conversion and HTTP stream driver. Preserve caller-supplied keys, base URLs, beta and session-affinity headers, timeouts and cancel semantics. Keep model policy and CLI transports in the provider. Record each legacy field with a tested mapping or an explicit caller-visible incompatibility. Disable automatic resubmission in the candidate transport.

Exercise Baikai complete and stream on a scripted HTTP endpoint. Then register that provider in Shikumi and run a schema-constrained prediction, separating schema enforcement from tool use. Run the Shikigami decision program with the same registration, a pinned model and fixture evidence sink. Test success, API failure and cancellation. Instrument the loopback endpoint with a counter and request IDs so a stub above the driver cannot accidentally pass. Preserve a replayable trial patch and focused fixtures in `integration/consumers/` with a short runbook identifying checkout revisions, configuration and actual commands. Keep this test project outside the default package dependency graph.

## Concrete Steps

Resolve source packages from the client repository root. Configure the trial Cabal project as described above, then from its directory run the package suites. If consumer tests require a repository fixture service, use that consumer's documented setup in its scratch checkout. Record the exact focused test invocations used for the three new scenarios.

```bash
mori path mori://shinzui/baikai/packages/baikai-claude
mori path mori://shinzui/shikumi/packages/shikumi
mori path mori://shinzui/shikigami/packages/shikigami-core
```

```bash
cabal test baikai-claude:test:baikai-claude-test --test-show-details=direct
cabal test shikumi:test:shikumi-test --test-show-details=direct
cabal test shikigami-core:test:shikigami-core-test --test-show-details=direct
```

Expect PASS from each target and captures from the trial HTTP driver in all three integration scenarios.

## Validation and Acceptance

Check the Cabal build plan selects the local candidate for the ported adapter. At Baikai, capture two consecutive tool rounds including signed empty and redacted thinking, a schema without tools, a cached prompt, and a canceled stream. Assert matching tool IDs, cache counts and released resources. At Shikumi, decode the schema fixture into the predicted fields and confirm a 429 retains typed failure evidence for its retry decision. At Shikigami, compare observed dispatch count and attempt records including correlation and reported usage. On a terminal failure or cancellation the client must never create an extra wire attempt. Reapply the recorded patch to fresh copies at the recorded revisions and reproduce the focused checks. Preserve the patch for adoption review.

## Idempotence and Recovery

Use fresh temporary work directories and synthetic keys per run. Inspect any build failure against the consumer's baseline at the same revision, then fix the smallest provider mapping or client defect and repeat. Keep the original consumer checkouts available as the comparison point.

## Interfaces and Dependencies

Begin when `docs/plans/2-stream-message-events-as-they-arrive.md` and `docs/plans/4-support-current-claude-reasoning-tools-caching-and-citations.md` are complete. They supply complete and streaming Messages operations on one client. The new package stays downstream-independent. Compatibility changes discovered here belong to the owning client module and its regression fixture. Batch lifecycle support is independent of this consumer proof.

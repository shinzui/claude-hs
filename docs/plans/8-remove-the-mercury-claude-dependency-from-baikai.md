---
id: 8
slug: remove-the-mercury-claude-dependency-from-baikai
title: "Remove the Mercury Claude dependency from Baikai"
kind: exec-plan
created_at: 2026-11-20T21:15:41Z
master_plan: "docs/masterplans/2-reach-mercury-claude-feature-parity-and-migrate-baikai.md"
provenance:
  created_by:
    model: "gpt-6.2-sol"
    harness: "codex-cli"
    at: 2026-11-20T21:15:41Z
---

# Remove the Mercury Claude dependency from Baikai

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

## Purpose / Big Picture

Baikai's public Claude HTTP provider builds against `claude-hs` alone for the Anthropic protocol. Its callers retain the same structured output, tool continuation, billing evidence, error and cancellation behavior. The dependency is ready to switch when a fresh build selects the new package and neither source imports nor the resolved closure contain Mercury `claude`.

## Progress

- [ ] A clean Baikai checkout switches request mapping and event assembly to the candidate, and the full provider suite builds and passes with Mercury absent from imports and the resolved dependency graph.
- [ ] The pinned downstream cohort passes against that Mercury-free adapter, and the migration patch and release prerequisites are reproducible from fresh checkouts.

## Surprises & Discoveries

The transport-only patch applied cleanly in a disposable checkout of `mori://shinzui/baikai/repos/baikai` at `87481ea7ff867a37bf602b0dc1ac8caa9e2e2710`. Its own locked shell passed all 475 provider tests. The plan contained both packages, so this is the migration baseline. It exercised both public call paths, signed tool turns and live socket cancellation with synthetic credentials.

## Decision Log

## Outcomes & Retrospective

## Context and Orientation

The consumer is `mori://shinzui/baikai/packages/baikai-claude`. The [transport-only trial](../../integration/consumers/README.md) passes a provider-shaped request to `streamMessageValue` and re-decodes candidate event JSON into Mercury event types. The mapper in `Baikai.Provider.Claude.Internal.Request`, shaping and header helpers in `Baikai.Provider.Claude.Shape` and `Baikai.Provider.Claude.Transport`, and event handling in `Baikai.Provider.Claude.Sse` and `Baikai.Provider.Claude.Internal.Stream` import Mercury types. Several provider tests also import them. The Baikai transport helpers are exposed for development and carry their documented stability policy. Keep the first-class provider entry points and both complete and stream paths. The [local HTTP ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) assigns scoped response cleanup and forbids automatic HTTP replay. The [replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) preserves opaque provider objects.

`mori://shinzui/shikumi/okf/adrs/concepts/ADR-11` requires structured provider failures and `mori://shinzui/shikumi/okf/adrs/concepts/ADR-14` separates schema enforcement from tool calling. For the following filesystem ADRs the artifact-level URI is pending. `mori://shinzui/baikai` with `docs/adr/0010-a-stream-consumer-that-stops-owns-cancelling-the-producer.md` assigns stream cancellation to the consumer. `mori://shinzui/baikai` with `docs/adr/0019-reasoning-continuation-is-scoped-to-its-provider-and-model.md` requires faithful same-model reasoning replay. `mori://shinzui/shikigami` with `docs/adr/0043-decision-provider-wrappers-own-actual-attempt-boundaries.md` requires one recorded boundary per real dispatch.

## Plan of Work

Start with clean checkouts of current Baikai and its compatible downstream cohort. Keep the Mercury-backed checkout as the baseline. Adapt the existing candidate patch to use completed request types. Retain Baikai's normalisation of tool IDs, provider and model restrictions, scoped reasoning replay, schema and tool independence, cache shaping, header overrides and timeout ownership. Route legacy opt-ins through the configured legacy version and test the user-visible migration error for removed fields when Baikai explicitly selects the new version. Preserve the final semantic request and evidence digest in the existing version. Keep subscription CLI behavior owned by Baikai.

Consume the candidate's typed stream events in the actual assembler and use its raw content only for opaque provider data. Preserve known refusal reasons and details, tool and thinking fragments, cache read/write usage, thinking token breakdown, service tier, speed, billing facts, correlation ID precedence and structured HTTP errors including Retry-After. Rework the old manager-injection and ByteString framing fixtures using candidate event or loopback seams. Preserve the behavior those fixtures prove, including redirects, partial stream termination, confirmation of pending reads before cancellation, and socket closure. Keep error classification under Baikai's public contract and caller retry policy above the provider.

Remove the `claude` library from both Baikai library and test build dependencies. Remove stale bounds overrides or package constraints from any successfully migrated downstream project if their resolver still names the old package. Update package registration and dependency docs as part of the adopted change. Save a patch against the recorded current consumer revisions, a reproducible Cabal project selecting the candidate, and before/after evidence in `integration/consumers/`. Exercise downstream using the local no-Mercury candidate before planning a published upgrade. For release readiness, verify that downstream can select a consumable version of `claude-hs` through its normal release path and document the order for publishing the library and updating Baikai. Use the previously accepted transport trial as a rollback reference if publication or consumer validation is pending.

## Concrete Steps

To reproduce the transport-only baseline, create a detached copy of the recorded Baikai revision, apply the existing trial patch and add the local candidate to `cabal.project.local` as a package. Run from the copied Baikai root.

```bash
nix develop --no-write-lock-file -c env -u ANTHROPIC_API_KEY -u ANTHROPIC_KEY \
  cabal test baikai-claude:test:baikai-claude-test --test-show-details=direct \
  --test-options='--num-threads=1 +RTS -N4 -RTS' -j8
```

Use Mori from the client repository to locate the active source checkouts. Copy the pinned-consumer setup in [the runbook](../../integration/consumers/README.md) into a fresh trial project and select the new patch and candidate. Run from that trial project's root.

```bash
mori path mori://shinzui/baikai/packages/baikai-claude
mori path mori://shinzui/shikumi/packages/shikumi
mori path mori://shinzui/shikigami/packages/shikigami-core
```

```bash
nix develop --no-write-lock-file -c env -u ANTHROPIC_API_KEY -u SHIKUMI_LIVE   cabal test baikai-claude:test:baikai-claude-test shikumi:test:shikumi-test   shikigami-core:test:shikigami-core-test --test-show-details=direct   --test-options='--num-threads=1 +RTS -N4 -RTS'
jq -e '[."install-plan"[] | select(."pkg-name"=="claude")] | length == 0'   dist-newstyle/cache/plan.json
jq -e 'any(."install-plan"[]; ."pkg-name"=="claude-hs" and ."pkg-src".type=="local")'   dist-newstyle/cache/plan.json
```

Check source and build dependency declarations in the disposable checkouts for imports of `Claude.V1` and dependencies on the exact Cabal package name `claude`. Treat matches for binaries, providers and model names according to their context. Record the commands, revisions and solver evidence.

## Validation and Acceptance

Require full provider suite PASS through the actual public complete and stream paths. Compare baseline and migrated captured requests for a schema-only request, strict tool selection, two consecutive tool rounds with empty signed and redacted reasoning, a cached prompt and a legacy sampling request. Compare billing evidence and refusal details. Verify HTTP status, Retry-After and correlation through the structured Shikumi error path. For Shikigami, assert one request and one attempt record on success, terminal failure and cancellation, with correlation and usage when reported and no transport replay. Reapply the patch against fresh copies of the recorded consumer revisions and reproduce the evidence. Verify Cabal selects `claude-hs` and contains no `claude` package. Report the production adoption and dependency-release prerequisites separately from trial acceptance.

## Idempotence and Recovery

Use detached throwaway checkouts, synthetic credentials and loopback traffic. Recreate the project from recorded revisions before rerunning a failed solver or fixture command. Keep the prior adapter available at its released revision for rollback.

## Interfaces and Dependencies

Requires [request and tool parity](6-complete-claude-messages-request-and-tool-feature-coverage.md) and [response and streaming parity](7-preserve-advanced-claude-response-and-streaming-evidence.md) complete. They provide the request types for the mapper and the response observations for the assembler. Baikai owns provider policies and its stable provider interfaces. The candidate owns HTTP transport and protocol codecs.

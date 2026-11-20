---
id: 2
slug: reach-mercury-claude-feature-parity-and-migrate-baikai
title: "Reach Mercury Claude feature parity and migrate Baikai"
kind: master-plan
created_at: 2026-11-20T21:15:41Z
provenance:
  created_by:
    model: "gpt-6.2-sol"
    harness: "codex-cli"
    at: 2026-11-20T21:15:41Z
  reviews:
    - model: "gpt-6.2-astra"
      harness: "codex-cli"
      at: 2026-11-20T21:57:23Z
      verdict: "changes-requested"
      note: "Define the Baikai adoption gate and assign a wire-level continuation check across the library plans."
  revisions:
    - model: "gpt-6.2-astra"
      harness: "codex-cli"
      at: 2026-11-20T22:03:12Z
      mode: "update"
      note: "Assign two-turn continuation to EP-7 and require a clean adopted Baikai revision."
    - model: "gpt-6.2-sol"
      harness: "codex-cli"
      at: 2026-11-20T22:29:30Z
      mode: "implement"
      note: "Coordinate request and response parity and Baikai adoption."
---

# Reach Mercury Claude feature parity and migrate Baikai

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

## Vision & Scope

Make `claude-hs` a functional superset of the released `mori://MercuryTechnologies/claude/packages/claude` 1.5.0 package. Applications can use every valid Messages workflow supported by that baseline through the new package's API. Preserve its supported request options, response observations and continuation behavior, plus the already accepted citation and incremental batch result support. Baikai uses the new package for request shaping, HTTP and stream observations and removes the Mercury library from its resolved dependency graph. Completion requires a recorded adoption commit in `mori://shinzui/baikai/repos/baikai` whose clean checkout passes the provider suite with its ordinary dependency configuration. The compatibility target is API behavior. The stable Baikai provider API remains the migration boundary, and callers of Mercury's Haskell modules migrate their imports and types. [Released package](https://hackage-content.haskell.org/package/claude-1.5.0)

## Decomposition Strategy

The [first MasterPlan](1-build-a-haskell-client-for-the-claude-messages-api.md) established endpoint coverage and verified a transport-only trial. Preserve its outcomes as historical evidence. The new work splits outgoing requests and tool declarations from incoming observations so each can be verified over HTTP independently. Baikai then depends on both to remove its old request mapper types and event decoder projection. Existing endpoints continue to share the [HTTP boundary](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) and the [content replay rules](../adr/0003-preserve-provider-content-for-assistant-replay.md).

Compare against the released Hackage sources for `Claude.V1`, `Claude.V1.Error`, `Claude.V1.Messages`, `Claude.V1.Messages.Batches` and `Claude.V1.Tool`. The Mori corpus files were checked against the 1.5.0 source tarball. Both clients provide create and stream Messages, count tokens, and create, retrieve, list and cancel batches. `claude-hs` also reads batch results incrementally. The remaining typed parity gaps are advanced message options and tool definitions, structured response evidence, certain history forms, and version-dependent legacy request options. The two library plans list the individual capabilities and own the parity inventory in [Messages coverage](../messages-coverage.md).

## Exec-Plan Registry

| # | Title | Path | Hard deps | Soft deps | Status |
|---|---|---|---|---|---|
| EP-6 | Complete Claude Messages request and tool feature coverage | [6-complete-claude-messages-request-and-tool-feature-coverage.md](../plans/6-complete-claude-messages-request-and-tool-feature-coverage.md) | None | None | Complete |
| EP-7 | Preserve advanced Claude response and streaming evidence | [7-preserve-advanced-claude-response-and-streaming-evidence.md](../plans/7-preserve-advanced-claude-response-and-streaming-evidence.md) | Two-turn fixture only: EP-6 continuation inputs milestone | None | Complete |
| EP-8 | Remove the Mercury Claude dependency from Baikai | [8-remove-the-mercury-claude-dependency-from-baikai.md](../plans/8-remove-the-mercury-claude-dependency-from-baikai.md) | EP-6, EP-7 | None | Not Started |

## Dependency Graph

Start with EP-6 and EP-7. Their request and response fixtures run independently against the existing HTTP client. EP-8 requires accepted request construction and response observations so it can remove both sets of Mercury imports in the same adoption. Early compatibility checks within EP-6 and EP-7 compile one characteristic Baikai mapping and one refusal and usage event projection in a disposable checkout. EP-6 delivers typed continuation inputs and version-specific history admission as an early milestone. Once its outgoing fixture passes, EP-7 exercises the public response conversion in a two-turn HTTP fixture. Its incoming decoder work can start immediately. EP-8 starts after both library plans are complete.

## Integration Points

EP-6 owns the outgoing request envelope and option validation in `src/Claude/Messages.hs`, including shared encoding for stream, count and batch requests. It owns the outgoing types within `src/Claude/Messages/Features.hs`. EP-7 owns the incoming envelope and usage types in `Claude.Messages`, response block decoding in `Claude.Messages.Features`, and event observations in `Claude.Streaming`. EP-7 owns the public response-to-request conversion. Both plans coordinate on the existing opaque history block and original event object so tool, fallback and container state can survive a turn. EP-6 owns admission of sendable history forms by API version. EP-7 owns the two-turn fixture and the captured second request, including the container ID and the ordered history admitted by the selected wire contract. Each plan owns its feature rows in `docs/messages-coverage.md` and its own loopback fixtures.

EP-8 owns the migration patch, downstream regressions and final adoption in Baikai. It records two solver results, one from the pinned trial and one from a fresh checkout of the adoption commit. Start from the existing [trial runbook](../../integration/consumers/README.md) and use one buildable snapshot of the new package in the real Baikai provider. Compare semantic request JSON, response evidence and tool replay against the same provider revision with Mercury. Preserve Baikai's choice of host, model, version, metadata and timeout policy. Check one accounted attempt per dispatch under the Shikigami runtime and retain Shikumi's typed failure mapping. Record revised cross-project ownership in an ADR when the adoption is implemented.

## Progress

The endpoint and transport baseline has already passed. On 2026-11-20 the transport-only patch applied cleanly to `mori://shinzui/baikai/repos/baikai` at `87481ea7ff867a37bf602b0dc1ac8caa9e2e2710` and all 475 provider tests passed in that checkout's locked shell. The resolved plan selected both local `claude-hs` and Hackage `claude` 1.5.0. Request and response parity passed the locked-shell producer suite and the [pinned Baikai projections](../../integration/consumers/baikai-parity-projections.patch). The two-turn Messages fixtures captured PTC and fallback history through the public encoder. The Mercury-free cohort trial and clean Baikai adoption build remain open.

## Surprises & Discoveries

Baikai currently uses five production modules that import Mercury types. Its mapper and stream assembler use fields missing from the candidate's typed API, including legacy sampling on eligible models, detailed refusals, reasoning counts, service tier and speed. The checked-in adapter trial migrates transport and keeps Mercury in both its mapping and its event projection.

## Decision Log

2026-11-20. Measure the superset against valid Mercury 1.5.0 workflows and the explicit wire version. Keep the direct API default at 2026-10-21 and retain supported legacy fields on the 2023-06-01 path. This lets the Baikai migration preserve existing request commitments without changing its model policy. [Anthropic API migration](https://platform.claude.com/docs/en/api/migration-2026-10-21)

2026-11-20 review revision. Give EP-7 the continuation check because separate encoder and decoder fixtures can pass with incompatible history. Give EP-8 the final Baikai build because a trial patch alone cannot establish adoption.

## Outcomes & Retrospective

---
id: 6
slug: complete-advanced-messages-controls-and-signed-compaction
title: "Complete advanced Messages controls and signed compaction"
kind: master-plan
created_at: 2026-11-21T03:23:04Z
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:04Z
---

# Complete advanced Messages controls and signed compaction

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

## Vision & Scope

A caller can select the service tier, inspect cache diagnostics, use container skills and remote MCP, redeem a fallback credit, and replace long history with an explicitly requested signed summary.

## Decomposition Strategy

Separate request projection from compaction semantics. The first child owns the matrix of endpoint fields, headers and response evidence. Signed compaction adds a new operation with history replacement and streamed deltas, requiring an end-to-end replay test of its own.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) assigns HTTP cleanup and attempt ownership. The [assistant replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) preserves original provider objects and scopes continuation to the originating provider and model.

## Exec-Plan Registry

| Child | Deliverable | Hard prerequisites | Status |
|---|---|---|---|
| [EP-16](../plans/16-carry-advanced-request-controls-across-messages-endpoints.md) | Carry advanced request controls across Messages endpoints | None | Not Started |
| [EP-17](../plans/17-compact-a-conversation-and-replay-its-signed-summary.md) | Compact a conversation and replay its signed summary | [EP-10](../plans/10-fold-message-events-into-a-complete-response.md) | Not Started |

## Dependency Graph

[EP-16](../plans/16-carry-advanced-request-controls-across-messages-endpoints.md) can start immediately. [EP-17](../plans/17-compact-a-conversation-and-replay-its-signed-summary.md) depends on [EP-10](../plans/10-fold-message-events-into-a-complete-response.md) for its streamed compaction criterion. Reconcile their additive request settings in the shared encoder.

## Integration Points

EP-16 owns additive configuration and the documented create/count/stream/batch matrix. EP-17 owns the compaction configuration, block decoder, stop reason, delta handling and history replacement. EP-13 owns the separate thread request field. Extend the same configuration entry points when both land. Run the existing container/fallback fixtures and compare the raw second POST after a signed summary before broadening compaction support.

## Progress

EP-16 is ready. EP-17 consumes EP-10’s fold for compaction stream parity. EP-16 and EP-17 coordinate the shared encoder, but the compaction protocol does not depend on service tier or MCP.

## Surprises & Discoveries

## Decision Log

2026-11-20. Keep triggered context-management edits available to existing callers. Explicit summarization has different request compatibility, failure and replay rules.

## Outcomes & Retrospective

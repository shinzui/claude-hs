---
id: 3
slug: assemble-streamed-claude-responses-for-conversation-replay
title: "Assemble streamed Claude responses for conversation replay"
kind: master-plan
created_at: 2026-11-21T03:23:03Z
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:03Z
---

# Assemble streamed Claude responses for conversation replay

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

## Vision & Scope

A caller can display live output and obtain a complete assistant message for the next turn from one request. Existing event-only consumers retain their early-stop and memory behavior.

## Decomposition Strategy

Separate event assembly from the connection lifetime. A pure fold can be verified against a unary response and reused by anyone who already consumes events. The HTTP wrapper then owns only one call’s state and terminal result.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) assigns HTTP cleanup and attempt ownership. The [assistant replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) preserves original provider objects and scopes continuation to the originating provider and model.

## Exec-Plan Registry

| Child | Deliverable | Hard prerequisites | Status |
|---|---|---|---|
| [EP-10](../plans/10-fold-message-events-into-a-complete-response.md) | Fold message events into a complete response | None | Not Started |
| [EP-11](../plans/11-return-the-assembled-message-from-a-live-stream.md) | Return the assembled message from a live stream | [EP-10](../plans/10-fold-message-events-into-a-complete-response.md) | Not Started |

## Dependency Graph

[EP-10](../plans/10-fold-message-events-into-a-complete-response.md) → [EP-11](../plans/11-return-the-assembled-message-from-a-live-stream.md). The wrapper requires a fold that produces a validated message or a precise failure.

## Integration Points

EP-10 owns ordering, delta semantics and the consistency between `MessageResponse`, `responseJSON` and replay. EP-11 owns callback timing, teardown and the result returned on stop. Its first integration fixture feeds a streamed tool call to `continueMessage` and compares the next request with its unary equivalent.

## Progress

EP-10 is ready. EP-11 needs the completed fold. EP-19 will consume the completed streaming entry point.

## Surprises & Discoveries

## Decision Log

2026-11-20. A completed response is shared by both generation paths. Keep collection opt-in so event-only consumers can process arbitrarily long output without retaining a second copy.

## Outcomes & Retrospective

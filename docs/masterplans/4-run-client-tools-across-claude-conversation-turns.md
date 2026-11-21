---
id: 4
slug: run-client-tools-across-claude-conversation-turns
title: "Run client tools across Claude conversation turns"
kind: master-plan
created_at: 2026-11-21T03:23:03Z
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:03Z
---

# Run client tools across Claude conversation turns

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

## Vision & Scope

A Haskell application registers local handlers, submits a conversation and receives the terminal assistant response after one or more tool turns. Applications can opt into a server-held Messages thread to send smaller continuation requests.

## Decomposition Strategy

Ship the full-history runner first. Tool dispatch, handler outcomes and call-ID correlation can be exercised against the existing unary endpoint. The second child changes the representation of history on the wire and reuses the same dispatch contract.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) assigns HTTP cleanup and attempt ownership. The [assistant replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) preserves original provider objects and scopes continuation to the originating provider and model.

## Exec-Plan Registry

| Child | Deliverable | Hard prerequisites | Status |
|---|---|---|---|
| [EP-12](../plans/12-execute-registered-client-tools-across-message-turns.md) | Execute registered client tools across message turns | None | Not Started |
| [EP-13](../plans/13-continue-tool-conversations-with-server-held-threads.md) | Continue tool conversations with server held threads | [EP-12](../plans/12-execute-registered-client-tools-across-message-turns.md) | Not Started |

## Dependency Graph

[EP-12](../plans/12-execute-registered-client-tools-across-message-turns.md) → [EP-13](../plans/13-continue-tool-conversations-with-server-held-threads.md). Thread continuation consumes the runner’s confirmed transcript and already-executed tool results.

## Integration Points

EP-12 owns the handler registry, correlated tool results, completed history and turn limit in `Claude.Tools`. EP-13 owns the thread handle and request fingerprint. The first threaded integration fixture must run the same registered handler once and show that the next request carries only the result plus the previous response ID. Expose pause, refusal and cancellation outcomes to the application.

## Progress

EP-12 can start from `createMessage` today. EP-13 depends on its accepted runner. The completed stream from MP-3 is a compatible turn source, with no dependency for unary execution.

## Surprises & Discoveries

## Decision Log

2026-11-20. Handlers remain application-supplied. Keep server retention and any recovery request explicit to preserve caller control over side effects and attempts.

## Outcomes & Retrospective

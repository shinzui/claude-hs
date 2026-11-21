---
id: 7
slug: parse-structured-claude-outputs-into-haskell-values
title: "Parse structured Claude outputs into Haskell values"
kind: master-plan
created_at: 2026-11-21T03:23:04Z
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:04Z
---

# Parse structured Claude outputs into Haskell values

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

## Vision & Scope

A caller can pair a JSON Schema with a Haskell decoder, request structured output, and inspect either a typed result or the reason parsing could not complete, with the original message available in both cases.

## Decomposition Strategy

First deliver parsing as a pure consumer of any `MessageResponse`, including a response from batch results. Bind it to unary and streaming generation only after the model of refusal, truncation and multiple text blocks is tested.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) assigns HTTP cleanup and attempt ownership. The [assistant replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) preserves original provider objects and scopes continuation to the originating provider and model.

## Exec-Plan Registry

| Child | Deliverable | Hard prerequisites | Status |
|---|---|---|---|
| [EP-18](../plans/18-decode-schema-constrained-message-responses.md) | Decode schema constrained message responses | None | Not Started |
| [EP-19](../plans/19-request-and-parse-structured-outputs-across-unary-and-streaming-calls.md) | Request and parse structured outputs across unary and streaming calls | [EP-18](../plans/18-decode-schema-constrained-message-responses.md), [EP-11](../plans/11-return-the-assembled-message-from-a-live-stream.md) | Not Started |

## Dependency Graph

[EP-18](../plans/18-decode-schema-constrained-message-responses.md) and [EP-11](../plans/11-return-the-assembled-message-from-a-live-stream.md) → [EP-19](../plans/19-request-and-parse-structured-outputs-across-unary-and-streaming-calls.md). The generation helpers need both a parser and a completed stream.

## Integration Points

EP-18 owns the schema/decoder pair, parsed values and block-indexed outcomes. EP-19 owns schema installation, request execution and metadata. It consumes EP-11 for stream completion. Compare the decoded application record from a synchronous reply and fragmented SSE containing identical JSON.

## Progress

EP-18 can start now. EP-19 depends on the accepted parser and the live stream collector. Neither model discovery nor automatic schema inference is required.

## Surprises & Discoveries

## Decision Log

2026-11-20. Use an explicit schema/decoder pair so consumers can keep their existing Haskell data types and choose the level of application validation.

## Outcomes & Retrospective

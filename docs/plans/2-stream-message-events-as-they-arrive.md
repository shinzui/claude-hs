---
id: 2
slug: stream-message-events-as-they-arrive
title: "Stream message events as they arrive"
kind: exec-plan
created_at: 2026-11-20T19:36:14Z
master_plan: "docs/masterplans/1-build-a-haskell-client-for-the-claude-messages-api.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-20T19:36:14Z
  revisions:
    - model: "gpt-6.2-astra"
      harness: "codex-cli"
      at: 2026-11-20T20:25:29Z
      mode: "update"
      note: "Use the Seihou-generated Nix development shell for client builds and tests."
---

# Stream message events as they arrive

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

Deliver typed Claude events while a request is still running, so a Baikai consumer can display text, assemble tool input, retain signed reasoning and stop generation.

## Progress

- [ ] A public callback receives the first event before the server sends the rest, and stopping releases the response.
- [ ] Fragmentation, new feature events, in-stream errors and premature closure pass the fixture suite.

## Surprises & Discoveries



## Decision Log



## Outcomes & Retrospective



## Context and Orientation

Begin after `docs/plans/1-send-messages-and-count-input-tokens.md` is complete. It supplies a buildable package, the public `Claude.Messages` types, a reusable `Claude.Client`, typed `ClientError`, a bracketed internal HTTP response reader and a loopback test server. Also require `docs/plans/4-support-current-claude-reasoning-tools-caching-and-citations.md` complete for content, citation, tool and thinking types. Server-sent events (SSE) are UTF-8 text records separated by blank lines. Socket reads may split anywhere. For the following filesystem ADRs the artifact-level URI is pending. `mori://shinzui/baikai` plus `docs/adr/0010-a-stream-consumer-that-stops-owns-cancelling-the-producer.md` assigns cancellation to the stream consumer. `mori://shinzui/baikai` plus `docs/adr/0019-reasoning-continuation-is-scoped-to-its-provider-and-model.md` requires faithful replay within the same model and provider. `mori://shinzui/shikigami` plus `docs/adr/0043-decision-provider-wrappers-own-actual-attempt-boundaries.md` assigns attempt accounting to the calling runtime. Follow `mori://shinzui/haskell-jitsurei/docs/core-standards` and `mori://shinzui/haskell-jitsurei/docs/core-record-patterns`. Use strict record fields, explicit deriving strategies, postpositive qualified imports and generic-lens labels for access and updates. Use explicit wire keys wherever the protocol differs from Haskell naming.

## Plan of Work

Create `src/Claude/Streaming.hs` and a private incremental SSE decoder. Use the Messages encoder with stream enabled and request text/event-stream. Use the scoped reader and invoke a synchronous callback with a continue/stop decision so a slow caller applies backpressure. Start with a coordinated server that flushes message_start then waits for the callback. Prove delivery and prompt release on caller stop before extending the parser.

Buffer partial lines across reads, handle CRLF and LF, comments, multiline data and several records in one read. Decode event JSON after framing. Deliver message start, indexed block start/delta/stop, message delta and stop, including text, partial tool JSON, citation, thinking and signature deltas. Preserve unknown event or delta tags and payloads. Pass ordered fragments intact so consumers can finalize tool JSON at block stop. Surface a server error after HTTP success and unexpected EOF as typed failure. Never reconnect or replay after partial delivery. [Streaming protocol](https://platform.claude.com/docs/en/build-with-claude/streaming).

## Concrete Steps

From the repository root, build and test each client milestone in the locked development shell provided by EP-1. See the [tooling ADR](../adr/0001-bootstrap-haskell-tooling-with-seihou.md). The library must build and the local test suite must report PASS with no Anthropic key in the environment.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test all --test-show-details=direct
```

## Validation and Acceptance

Add `test/StreamingSpec.hs`. Send the same transcript whole and split at every individual byte (including within a non-ASCII character). Both yield identical events, indices, citation locations, signature, cumulative usage and stop reason. Script a two-turn tool call containing signed reasoning and verify the consumer can replay the signature and matching tool ID in the next Messages request. Run the gated first-event fixture with a bounded timeout. Cover explicit early stop, asynchronous cancellation, callback failure, ping, malformed known event, server error and missing message_stop. Observe resource release on each exit and distinguish early stop from provider completion.

## Idempotence and Recovery

Fixture streams use gates released in cleanup, including failure paths. Replay local transcripts freely. Production callers decide whether to start a new request after an interruption.

## Interfaces and Dependencies

Expose streamMessage with the shared Client and MessageRequest, a typed StreamEvent callback returning Continue or Stop, and a typed terminal result distinguishing finished, stopped and error. The caller owns event accumulation, model-scoped continuation and downstream retry policy. Consume the accepted feature codecs for block starts.

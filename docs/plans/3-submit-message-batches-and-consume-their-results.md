---
id: 3
slug: submit-message-batches-and-consume-their-results
title: "Submit message batches and consume their results"
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

# Submit message batches and consume their results

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

A caller can submit independent Messages requests as one batch, inspect its progress, cancel it, and process each result by the original custom ID.

## Progress

- [ ] Create, retrieve, list and cancel use the expected routes and typed metadata.
- [ ] A consumer receives mixed outcomes incrementally and matches each result by custom ID.

## Surprises & Discoveries



## Decision Log



## Outcomes & Retrospective



## Context and Orientation

Begin after `docs/plans/1-send-messages-and-count-input-tokens.md` is complete. It supplies a buildable package, the public `Claude.Messages` types, a reusable `Claude.Client`, typed `ClientError`, a bracketed internal HTTP response reader and a loopback test server. A batch runs asynchronously. Its results are newline-delimited JSON objects and can arrive in a different order from the inputs. Follow `mori://shinzui/haskell-jitsurei/docs/core-standards` and `mori://shinzui/haskell-jitsurei/docs/core-record-patterns`. Use strict record fields, explicit deriving strategies, postpositive qualified imports and generic-lens labels for access and updates. Use explicit wire keys wherever the protocol differs from Haskell naming. There is no batch-specific local ADR. `mori://shinzui/shikumi/okf/adrs/concepts/ADR-11` requires structured failures for downstream retry decisions. `mori://shinzui/shikumi/okf/adrs/concepts/ADR-14` distinguishes schema enforcement from tool calling.

## Plan of Work

Create `src/Claude/Batches.hs` with custom ID, batch ID, processing status, request counts, nullable result location, timestamps, and a page carrying cursor metadata. Use the shared Messages request codec for params. Check nonempty and unique custom IDs before submitting. Implement POST and GET on /v1/messages/batches, GET by ID and POST to the ID's cancel subresource. Test one cursor page in each direction and cancellation followed by a fresh retrieve. Expose observed status so applications can schedule their own polling.

Fetch results from the documented results endpoint on the configured origin. Consume the body incrementally and decode one result per line, retaining custom ID for succeeded, errored, canceled and expired outcomes. A succeeded result uses the shared MessageResponse codec. Decoding and HTTP failures are distinct from per-item errors. [Batch lifecycle and results](https://platform.claude.com/docs/en/build-with-claude/batch-processing).

## Concrete Steps

From the repository root, build and test each client milestone in the locked development shell provided by EP-1. See the [tooling ADR](../adr/0001-bootstrap-haskell-tooling-with-seihou.md). The library must build and the local test suite must report PASS with no Anthropic key in the environment.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test all --test-show-details=direct
```

## Validation and Acceptance

In `test/BatchesSpec.hs`, assert the captured submitted params equal a Messages fixture. Decode ISO timestamps and null result URL for a running batch. A paginated fixture must forward the cursor and expose has_more. Serve results in reverse input order with mixed outcomes and split lines across HTTP chunks. Verify first-result delivery before EOF, correct custom IDs, and clean handling of a malformed later line. Re-run the test with an enriched Messages fixture at final integration.

## Idempotence and Recovery

Use a fresh loopback batch per run. On ambiguous real submission failure return the error and available request ID. Leave reconciliation to the caller. A canceled batch may still yield successful items.

## Interfaces and Dependencies

Expose createBatch, retrieveBatch, listBatches, cancelBatch and a scoped result consumer. Reuse ClientError, MessageRequest and MessageResponse. Keep the line reader internal to Batches. Streaming SSE framing is independent of JSON lines.

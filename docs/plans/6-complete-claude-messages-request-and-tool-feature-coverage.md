---
id: 6
slug: complete-claude-messages-request-and-tool-feature-coverage
title: "Complete Claude Messages request and tool feature coverage"
kind: exec-plan
created_at: 2026-11-20T21:15:41Z
master_plan: "docs/masterplans/2-reach-mercury-claude-feature-parity-and-migrate-baikai.md"
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
      note: "Require legacy empty history on the typed Baikai mapper and verify current-version rejection before dispatch."
  revisions:
    - model: "gpt-6.2-astra"
      harness: "codex-cli"
      at: 2026-11-20T22:03:12Z
      mode: "update"
      note: "Exercise legacy empty history through the typed mapper and deliver continuation inputs early."
---

# Complete Claude Messages request and tool feature coverage

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

## Purpose / Big Picture

A caller can express every supported request that Mercury 1.5.0 could send, including deferred tools, programmatic tool calling and advanced Messages controls. The same request fields follow Anthropic's endpoint and API-version rules in synchronous calls, SSE, token counting and batches. A caller moving from the older wire version gets an explicit error for a sampling setting the selected newer version rejects.

## Progress

- [ ] The Baikai request mapping slice compiles and sends equivalent semantic JSON for a legacy request and a current schema request, including an empty legacy history and independent pre-dispatch failures for empty current history and removed sampling fields.
- [ ] Continuation inputs are ready for the response plan when a public request fixture sends a container ID and admitted tool and fallback history through the typed encoder under the selected version.
- [ ] The request and tool inventory is covered by endpoint and version fixtures, including a compound request using tool search and programmatic tool calling.

## Surprises & Discoveries

## Decision Log

## Outcomes & Retrospective

## Context and Orientation

`src/Claude/Messages.hs` defines `Conversation`, `MessageRequest`, `CountRequest` and the corresponding JSON encoders. `src/Claude/Messages/Features.hs` defines tools, thinking, caching and output configuration. `src/Claude/Streaming.hs` accepts typed or versioned JSON requests, and `src/Claude/Batches.hs` embeds the Messages request in a batch item. The library defaults to version 2026-10-21. Its JSON streaming bridge already rejects legacy sampling fields for that version and permits an empty older history. The typed `Conversation.messages` field currently requires `NonEmpty Message`, so the Baikai mapper cannot express an empty history through that API. Provide a typed construction path for the legacy form and validate the selected version at dispatch. Unary and batch requests use typed encoders. The [replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) keeps raw provider content available separately from caller-supplied content. The [tooling ADR](../adr/0001-bootstrap-haskell-tooling-with-seihou.md) pins the build shell.

Locate the released comparison through `mori://MercuryTechnologies/claude/packages/claude`. Check the exported requests, tool definitions and helpers in `Claude.V1.Messages` and `Claude.V1.Tool`, and the cache types they re-export. [Mercury 1.5.0](https://hackage-content.haskell.org/package/claude-1.5.0)

## Plan of Work

First compare the captured JSON from the request mapper in `mori://shinzui/baikai/packages/baikai-claude` with a small mapper using only the candidate request types. Use an eligible older model with temperature or top-p and an existing fixture with native JSON Schema independent of tools. Keep established model and host shaping in Baikai. Define shared endpoint validation so a typed request and a JSON bridge observe the same owned fields. Establish the field projection for token counting and nested batch params before adding the remaining types.

After the mapper slice, implement the container and history inputs and capture their wire encoding. Hand this fixture and its version-specific admission rules to the [response plan](7-preserve-advanced-claude-response-and-streaming-evidence.md) before expanding the tool inventory.

Cover Mercury's request metadata, context management and compaction options, inference geography, container reuse, server fallback settings and their valid history blocks. Check version and model restrictions for system messages inside conversation history, assistant tool calls with caller information, tool addition/removal and fallback markers, and the cache TTL forms accepted by each supported contract. Preserve older sampling fields `temperature`, `top_p` and `top_k` where the older contract accepts them. Keep existing output schema, thinking, speed and cache behavior. Include the released helper workflows in the inventory, with equivalent image source, structured schema and cache construction examples where the new API spelling differs. Support decoding a valid serialized request and emitting its supported fields again where useful for migration and fixtures.

Extend tool definitions with typed deferred loading, allowed callers, BM25 and regex tool search, programmatic tool calling and versioned code execution. A deferred tool is advertised without eagerly exposing its schema; tool search returns references that make those definitions available. Programmatic tool calling allows an Anthropic-managed code execution session to invoke a configured client tool. Model the versioned options and continuation inputs. Reuse `VersionedTool` and `VersionedBlock` for newly encountered provider tags. Add or update an example covering configuration of these features. Consult Anthropic's versioned contracts when a released Mercury option is older or beta. [Messages](https://platform.claude.com/docs/en/api/messages/create), [token counting](https://platform.claude.com/docs/en/api/messages/count_tokens), [API version migration](https://platform.claude.com/docs/en/api/migration-2026-10-21), [programmatic tool calling](https://platform.claude.com/docs/en/agents-and-tools/tool-use/programmatic-tool-calling)

## Concrete Steps

From the `claude-hs` repository root, locate both consumers and run the locked-shell build and tests.

```bash
mori path mori://MercuryTechnologies/claude/packages/claude
mori path mori://shinzui/baikai/packages/baikai-claude
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c env -u ANTHROPIC_API_KEY cabal test all --test-show-details=direct
```

Record one row per capability in [Messages coverage](../messages-coverage.md) with its fixture, valid endpoint and version, and any obsolete provider option and migration path.

## Validation and Acceptance

Capture the body through public HTTP calls. Compare the Baikai mapping slice and the Mercury request fixtures as semantic JSON. Send an otherwise valid, sampling-free request from the typed Baikai mapper through public streaming with version 2023-06-01. Assert the fixture server receives one request containing exactly `"messages": []`. Change only the version to 2026-10-21 and require an invalid-request result and zero dispatches. Separately check valid legacy sampling with a nonempty history. Check the same sampling keys are refused before dispatch on 2026-10-21, including on each affected typed endpoint. Exercise named legacy feature controls in requests and check the count projection excludes output limit, stop sequences and fields specific to generation. Exercise an enriched batch item and check its params match synchronous Messages without the stream flag. Confirm the pinned versioned tool names, required caller and deferred-loading fields, and beta tokens in the outgoing request. Demonstrate a request can carry a container ID and valid returned tool/fallback blocks in the appropriate conversation. Record that fixture as the continuation inputs milestone. EP-7 consumes its public API for the two-turn check.

## Idempotence and Recovery

Use synthetic keys and ephemeral servers. Keep the original Baikai checkout for comparison and create the mapper experiment in a disposable checkout. Keep invalid or retired provider options observable in version-specific fixtures.

## Interfaces and Dependencies

Own request types and admission for `Claude.Messages`, `Claude.Messages.Features`, `Claude.Streaming.streamMessageValue` and `Claude.Batches.createBatch`. Keep the original response block JSON and the `assistantContinuation` entry point available for EP-7. No prerequisite child plan.

---
id: 16
slug: carry-advanced-request-controls-across-messages-endpoints
title: "Carry advanced request controls across Messages endpoints"
kind: exec-plan
created_at: 2026-11-21T03:23:04Z
master_plan: "docs/masterplans/6-complete-advanced-messages-controls-and-signed-compaction.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:04Z
---

# Carry advanced request controls across Messages endpoints

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

## Purpose / Big Picture

Select service tier, diagnose a prompt-cache miss, configure container skills and remote MCP servers, and redeem eligible fallback credits from typed Messages calls.

## Progress

- [ ] Typed create, count, stream and batch requests project supported controls to their proper wire locations.
- [ ] A caller can use response diagnostics and fallback-credit evidence for a follow-up request.

## Surprises & Discoveries

## Decision Log

## Outcomes & Retrospective

## Context and Orientation

`src/Claude/Messages/Features.hs` separates common features from generation controls. `src/Claude/Messages.hs` projects those groups for count and generation and decodes known stop details. `src/Claude/Streaming.hs` and `src/Claude/Batches.hs` share the encoding. Existing container reuse uses a text ID.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) assigns HTTP cleanup and attempt ownership. The [assistant replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) preserves original provider objects and scopes continuation to the originating provider and model. The reviewed reference is TypeScript SDK tag `sdk-v1.12.0` (commit `3edf5eb`), `src/resources/beta/messages/messages.ts` in `mori://anthropics/anthropic-sdk-typescript` (artifact-level URI pending). [Pinned SDK source](https://github.com/anthropics/anthropic-sdk-typescript/blob/sdk-v1.12.0/src/resources/beta/messages/messages.ts)

## Plan of Work

Record a field-by-endpoint matrix in `docs/messages-coverage.md` from the stable and beta create, count and batch contracts. Include `service_tier`, `diagnostics.previous_message_id`, string/object `container` with skills, beta `mcp_servers` with MCP toolset declarations, and `fallback_credit_token` with any required beta header. The reviewed beta count endpoint admits MCP servers and context management. Generation-only service tier, diagnostics, container and fallback-credit redemption stay off count requests. Distinguish a field inside each batch item from headers scoped to batch creation. Define additive configuration preserving existing constructors, omission defaults and historical serialized requests. Carry fields through the typed SSE path as well. Represent returned diagnostics, credit token and redemption outcome while retaining raw provider evidence. Admit documented MCP result and use blocks for continuation, preserving IDs and order. Treat server auth tokens and fallback tokens as opaque credentials in displays and errors.

## Concrete Steps

Extend the existing `test/FeaturesSpec.hs` cases invoked by `test/Main.hs`. Expose any new public module under the Cabal library’s `exposed-modules`. Use `test/Support/Server.hs` for network fixtures and synthetic credentials.

Run from the repository root in the locked development shell.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test claude-hs-test --test-show-details=direct
```

Both commands should exit successfully and Cabal should report the client test suite passed.

## Validation and Acceptance

Send minimal and populated fixture requests through the four public paths. Assert full semantic bodies and headers, including the count subset and nested batch parameters. Exercise old `containerId`, container-with-skills, a mock MCP result replay, diagnostics returning null, a refusal yielding a credit, explicit credit redemption and usage evidence. Compare the second request exactly and verify fixture credentials are absent from error renderings. Include unexpected fields and model-specific provider rejections.

## Idempotence and Recovery

Test with synthetic MCP credentials and credits. A rejected provider request leaves the original request reusable. Keep credit redemption an explicit action on a distinct request.

## Interfaces and Dependencies

This plan can begin against the current library. Use the shared encoder for request fields and the existing `RequestOptions` beta mechanism. The caller decides whether to redeem credit. Thread ownership belongs to EP-13. EP-17 adds the distinct signed compaction operation.

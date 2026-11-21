---
id: 9
slug: discover-available-claude-models-and-their-capabilities
title: "Discover available Claude models and their capabilities"
kind: exec-plan
created_at: 2026-11-21T03:23:03Z
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:03Z
---

# Discover available Claude models and their capabilities

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

## Purpose / Big Picture

List models visible to a workspace, inspect the model behind an alias, and read its context window, output limit, lifecycle and advertised capabilities before constructing a Messages request.

## Progress

- [ ] Retrieve an alias and decode the returned canonical ID, lifecycle and nested capabilities.
- [ ] List and traverse a filtered catalogue across two pages in either cursor direction.
- [ ] Demonstrate lookup and pagination with the documented public API and existing client error handling.

## Surprises & Discoveries

## Decision Log

## Outcomes & Retrospective

## Context and Orientation

`src/Claude/Batches.hs` shows how `jsonRequest` sends a GET and decodes a cursor page. Its cursor contains a batch ID and is unsuitable for model IDs. `src/Claude/Internal/Http.hs` owns route prefixing, query rendering, credentials, beta headers and response metadata. Models have no public module in `claude-hs.cabal`.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) scopes credentials to the configured origin and leaves retries to the caller. The reviewed reference is TypeScript SDK tag `sdk-v1.12.0` (commit `3edf5eb`), `src/resources/models.ts` in `mori://anthropics/anthropic-sdk-typescript` (artifact-level URI pending). [Pinned SDK source](https://github.com/anthropics/anthropic-sdk-typescript/blob/sdk-v1.12.0/src/resources/models.ts) [List Models](https://platform.claude.com/docs/en/api/models/list) · [Get Model](https://platform.claude.com/docs/en/api/models/retrieve)

## Plan of Work

Create `src/Claude/Models.hs` and expose `ModelInfo`, `ModelCapabilities`, lifecycle, page and cursor types. Decode `id`, `type`, `display_name`, `created_at`, nullable `line`, `deprecated_at`, `retires_at`, `max_input_tokens`, `max_tokens` and nullable `capabilities`. Use UTC timestamps, nonnegative token counts and extensible text values for lines and lifecycle. Preserve unknown capability keys and original objects alongside typed observations. Cover batch, citations, code execution, image/PDF input, structured outputs, thinking types, effort levels, context-management strategies and server tools. Distinguish unreported capability details from explicit `supported: false`. A past retirement date alone cannot establish lifecycle.

Implement `retrieveModel` with `GET /v1/models/{id}` and `listModels` with `GET /v1/models`. Treat IDs and aliases as opaque path segments, encode reserved bytes and reject empty or dot segments before dispatch. A single cursor sum selects `after_id` or `before_id`. Omit absent options, support `limit` 1–1000 and up to three lifecycle filters as repeated `lifecycle[]` query keys. Workspace selection goes in `anthropic-workspace-id`, available through `RequestOptions.extraHeaders`. Decode `data`, `has_more`, `first_id` and `last_id`. Add a callback fold with early stop. Follow `last_id` forward and `first_id` backward, retain filters and workspace across pages, and surface a malformed or repeated cursor when the response claims another page. Fetch each page only as needed.

## Concrete Steps

Add `test/ModelsSpec.hs` to the test suite’s `other-modules` in `claude-hs.cabal` and call its `run` from `test/Main.hs`. Expose any new public module under the Cabal library’s `exposed-modules`. Use `test/Support/Server.hs` for network fixtures and synthetic credentials.

Run from the repository root in the locked development shell.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test claude-hs-test --test-show-details=direct
```

Both commands should exit successfully and Cabal should report the client test suite passed.

## Validation and Acceptance

Serve an alias with a different canonical ID, a null capability record, unknown model line and nested support flags including false. Assert the request method, escaped path, workspace header and empty GET body. Capture query pairs for default listing, forward and backward traversal with two lifecycle values, default omission and an explicit retired filter. Bound the request count on early stop, repeated cursor, missing cursor and an empty final page. Exercise invalid limit before dispatch, malformed JSON and HTTP 404 with request ID. Show a README example that looks up an alias and prints its advertised output limit.

## Idempotence and Recovery

Reads can be repeated against the local fixture. A fold can fail after delivering items. Return the page error and let the caller decide whether to restart from the last confirmed cursor.

## Interfaces and Dependencies

This plan can begin against the current library. Keep lookup independent of generation. Model discovery is a read-only description of provider capabilities. Existing Messages callers continue to choose their own models. Proposed signatures are `retrieveModel :: Client -> RequestOptions -> Text -> IO (Either ClientError (Response ModelInfo))` and `listModels :: Client -> RequestOptions -> ModelListOptions -> IO (Either ClientError (Response ModelPage))`. The model ID returned by retrieval can be used directly in the existing Conversation model field.

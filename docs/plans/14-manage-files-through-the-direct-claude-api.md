---
id: 14
slug: manage-files-through-the-direct-claude-api
title: "Manage files through the direct Claude API"
kind: exec-plan
created_at: 2026-11-21T03:23:04Z
master_plan: "docs/masterplans/5-use-files-and-document-artifacts-with-claude-messages.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:04Z
---

# Manage files through the direct Claude API

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

## Purpose / Big Picture

Upload files once and manage them on the configured API origin. Download generated output as bytes while the response is open.

## Progress

- [ ] Upload, list, retrieve and delete operate on typed file IDs and metadata.
- [ ] A scoped download emits binary chunks and propagates provider or transport errors.

## Surprises & Discoveries

## Decision Log

## Outcomes & Retrospective

## Context and Orientation

`src/Claude/Internal/Http.hs` currently accepts an optional JSON body, sets content headers and brackets the response reader. `src/Claude/Batches.hs` demonstrates a scoped incremental consumer. The Files list uses an opaque `next_page` cursor.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) scopes credentials to the configured origin and leaves retries to the caller. The reviewed reference is TypeScript SDK tag `sdk-v1.12.0` (commit `3edf5eb`), `src/resources/files.ts` in `mori://anthropics/anthropic-sdk-typescript` (artifact-level URI pending). [Pinned SDK source](https://github.com/anthropics/anthropic-sdk-typescript/blob/sdk-v1.12.0/src/resources/files.ts)

## Plan of Work

Add `src/Claude/Files.hs` with file ID, metadata, upload options and list page types. Extend the internal runner with a body/content-type representation that supports multipart uploads and preserves the JSON wrapper. Send a multipart `file` part with filename, MIME type and binary bytes, plus optional `expires_in_seconds`. Implement GET/POST `/v1/files`, GET/DELETE `/v1/files/{id}` and scoped GET `/v1/files/{id}/content`. Constrain IDs to a single path segment. Preserve expiry, size and downloadable status. Support page/limit and the alternative bounded IDs filter on list. Forward workspace selection through request headers.

## Concrete Steps

Add `test/FilesSpec.hs` to the test suite’s `other-modules` in `claude-hs.cabal` and call its `run` from `test/Main.hs`. Expose any new public module under the Cabal library’s `exposed-modules`. Use `test/Support/Server.hs` for network fixtures and synthetic credentials.

Run from the repository root in the locked development shell.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test claude-hs-test --test-show-details=direct
```

Both commands should exit successfully and Cabal should report the client test suite passed.

## Validation and Acceptance

Parse a synthetic multipart upload on loopback and compare its part bytes, filename and expiration. Return its ID and observe it on metadata and delete. Traverse two `next_page` values, capture ID filtering separately, and test missing/expired metadata. Download a tool-generated fixture with non-UTF-8 bytes in two chunks. Verify early stop/exception cleanup, a non-downloadable file error, and a truncated transfer. The normal Messages JSON fixtures still pass.

## Idempotence and Recovery

Repeat loopback transfers with a fresh fixture. On a partial download the sink already owns its delivered bytes. Upload and deletion each make a single attempt. Surface status and correlation metadata for an ambiguous completion.

## Interfaces and Dependencies

This plan can begin against the current library. The transport owns authentication, framing and response cleanup. Let applications select the upload source and download sink. Never use server-returned URLs as authenticated request targets. Share `FileId` with document inputs without introducing an import cycle.

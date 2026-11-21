---
id: 15
slug: send-typed-documents-and-consume-generated-file-references
title: "Send typed documents and consume generated file references"
kind: exec-plan
created_at: 2026-11-21T03:23:04Z
master_plan: "docs/masterplans/5-use-files-and-document-artifacts-with-claude-messages.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:04Z
---

# Send typed documents and consume generated file references

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

## Purpose / Big Picture

Use URL, base64, content-block and uploaded documents through typed Messages inputs, then download an artifact referenced by a code-execution result.

## Progress

- [ ] Document variants encode the same source and citation options in every applicable Messages operation.
- [ ] A code-execution result yields a typed file ID accepted by the downloader.

## Surprises & Discoveries

## Decision Log

## Outcomes & Retrospective

## Context and Orientation

`src/Claude/Messages/Features.hs` defines `PlainTextDocument`, code execution outcomes and raw block evidence. `src/Claude/Messages.hs` defines `InputDocument` and `VersionedBlock`. `src/Claude/Files.hs` from the prerequisite owns file IDs.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) assigns HTTP cleanup and attempt ownership. The [assistant replay ADR](../adr/0003-preserve-provider-content-for-assistant-replay.md) preserves original provider objects and scopes continuation to the originating provider and model. The reviewed reference is TypeScript SDK tag `sdk-v1.12.0` (commit `3edf5eb`), `src/resources/messages/messages.ts` in `mori://anthropics/anthropic-sdk-typescript` (artifact-level URI pending). [Pinned SDK source](https://github.com/anthropics/anthropic-sdk-typescript/blob/sdk-v1.12.0/src/resources/messages/messages.ts)

## Plan of Work

Extend the existing document type additively. Encode source tags for base64 PDF (`application/pdf`), URL PDF, content with admitted text/image blocks, and file with `file_id`. Preserve title, context, citations and cache controls. Keep the existing plain-text constructor and the opaque tagged input path. Follow the shared conversation encoder used by create, count, streaming and batches. From documented code-execution output entries extract ordered file IDs, keeping the surrounding original objects intact for replay.

## Concrete Steps

Extend the existing `test/FeaturesSpec.hs` cases invoked by `test/Main.hs`. Expose any new public module under the Cabal library’s `exposed-modules`. Use `test/Support/Server.hs` for network fixtures and synthetic credentials.

Run from the repository root in the locked development shell.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test claude-hs-test --test-show-details=direct
```

Both commands should exit successfully and Cabal should report the client test suite passed.

## Validation and Acceptance

Upload a synthetic PDF, use its returned ID in a user document, capture the Messages request, return a generated file ID in a tool-result block, and download its exact bytes. Also capture base64/URL/content variants and compare the nested document on count and batch endpoints. Exercise mixed output entries, absent file outputs, signed or unknown sibling content and epoch/version-dependent role validation.

## Idempotence and Recovery

Use a fresh loopback store for each test. Artifact extraction is pure and repeatable. A failed download leaves the decoded response available for caller-directed recovery.

## Interfaces and Dependencies

Hard prerequisites are [EP-14](../plans/14-manage-files-through-the-direct-claude-api.md), providing the accepted Files operations and FileId. The typed output accessor returns the `FileId` accepted by the Files client. It performs no network access. Preserve the existing consumer’s ability to opt into raw provider extensions.

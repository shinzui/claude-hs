---
id: 5
slug: use-files-and-document-artifacts-with-claude-messages
title: "Use files and document artifacts with Claude Messages"
kind: master-plan
created_at: 2026-11-21T03:23:04Z
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T03:23:04Z
---

# Use files and document artifacts with Claude Messages

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

## Vision & Scope

A caller can upload a document, reference it in a Messages request, inspect file IDs returned by code execution and stream a generated artifact into a sink.

## Decomposition Strategy

Give file lifecycle and binary transport to one child, and document encoding and artifact references to the other. This lets the client demonstrate a complete file operation before extending the Messages type family.

The [client lifetime ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) scopes credentials to the configured origin and leaves retries to the caller.

## Exec-Plan Registry

| Child | Deliverable | Hard prerequisites | Status |
|---|---|---|---|
| [EP-14](../plans/14-manage-files-through-the-direct-claude-api.md) | Manage files through the direct Claude API | None | Not Started |
| [EP-15](../plans/15-send-typed-documents-and-consume-generated-file-references.md) | Send typed documents and consume generated file references | [EP-14](../plans/14-manage-files-through-the-direct-claude-api.md) | Not Started |

## Dependency Graph

[EP-14](../plans/14-manage-files-through-the-direct-claude-api.md) → [EP-15](../plans/15-send-typed-documents-and-consume-generated-file-references.md). The document and artifact roundtrip consumes the public file ID and downloader.

## Integration Points

EP-14 owns `FileId`, file metadata, and scoped multipart/binary transport in `Claude.Files`. EP-15 consumes that ID in document sources and outputs. Its acceptance fixture uploads a PDF, captures the Messages file reference and downloads a different, generated file. Keep content-disposition and server-supplied filenames as metadata.

## Progress

EP-14 can start independently. EP-15 uses the accepted file ID and download operation. No model discovery or tool runner is required.

## Surprises & Discoveries

## Decision Log

2026-11-20. Keep network transfers explicit and preserve original output objects so reading a file reference cannot change replay.

## Outcomes & Retrospective

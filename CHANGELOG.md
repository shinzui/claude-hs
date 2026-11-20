# Changelog

## 0.1.0.0 (2026-11-20)

### New Features

- `Claude.Client` provides a reusable HTTP client with per-request beta headers, response request IDs, and typed transport, HTTP, and decoding errors.
- `Claude.Messages` and `Claude.Messages.Features` support synchronous messages and token counting, with structured outputs, thinking, prompt caching, citations, and client and server tools.
- `Claude.Messages` supports compaction, container reuse, server-side fallbacks, and continuation helpers for carrying typed tool results and response evidence across turns.
- `Claude.Streaming` delivers typed server-sent events incrementally and lets callers stop the stream from the event callback.
- `Claude.Batches` submits, retrieves, lists, and cancels message batches and consumes JSON Lines results incrementally.

### Other Changes

- Include a runnable Messages example and document request controls, supported API versions, and continuation behavior.

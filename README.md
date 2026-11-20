# claude-hs

Haskell client for the direct [Anthropic Messages API](https://platform.claude.com/docs/en/api/messages/create), using API version 2026-10-21.

```bash
nix develop --no-write-lock-file -c cabal update
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test all --test-show-details=direct
```

The loopback tests use synthetic credentials. To run the [example](example/Main.hs) against Anthropic, supply `ANTHROPIC_API_KEY` in the environment and run `nix develop -c cabal run claude-message-example`.

Create a `Client` once and share it across calls to reuse connections. `defaultClientConfig` uses `https://api.anthropic.com` and a 60-second HTTP response timeout. `RequestOptions` carries beta flags and additional metadata headers. Authentication, API version and framing headers are reserved. A `Response` carries the request ID where the server provides one. A `ClientError` distinguishes transport failures, HTTP status failures and JSON decoding errors. Applications own retry decisions.

See [Messages coverage](docs/messages-coverage.md) for request options, model restrictions and continuation behavior.

Use `Claude.Streaming.streamMessage` for SSE. The callback receives typed events synchronously and returns `Continue` or `Stop`. Inspect the terminal result for provider completion or caller stop. Keep partial output in the callback if the caller needs it after a stream failure.

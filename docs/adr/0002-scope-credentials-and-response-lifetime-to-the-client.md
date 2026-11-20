# Scope credentials and response lifetime to the client

Accepted on 2026-11-20.

A client owns a connection pool and sends its credentials to its configured endpoint. Disable HTTP redirects and stale-connection retries. The calling runtime owns attempt accounting and decides whether a failed call should be repeated.

Share one HTTP runner across unary, SSE and batch results. The runner brackets the response and gives endpoint code a reader valid for the duration of its callback. Asynchronous cancellation and caller exceptions unwind that scope. Transport errors, HTTP status failures and decode failures are distinct. Keep provider request IDs and Retry-After values available for callers. Render errors without credentials, headers or response bodies.

Integrators with multiple credential bindings can share a `ClientPool` while creating separate endpoint-scoped clients. Preserve the HTTP Date alongside Retry-After so the caller can interpret HTTP-date delays against the server clock. Bound and redact error excerpts while retaining status and correlation metadata.

Derive the batch results route from the original client origin and a validated batch ID. Expose the advertised results URL as metadata.

In the Baikai migration, `mori://shinzui/claude-hs/packages/claude-hs`
owns request encoding, connection pooling, SSE framing and typed event
decoding. `mori://shinzui/baikai/packages/baikai-claude` owns model and
host policy, cache and schema shaping, the selected wire version, error
classification and the whole-call timeout. Baikai translates the typed
client events into its stable provider contract. Its public complete and
stream paths use the same terminal evidence and cancellation behavior.

Baikai resolves the wire client through its ordinary Hackage configuration.
Disposable qualification checkouts can substitute a local candidate package.

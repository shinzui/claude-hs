# Scope credentials and response lifetime to the client

Accepted on 2026-11-20.

A client owns a connection pool and sends its credentials to its configured endpoint. Disable HTTP redirects and stale-connection retries. The calling runtime owns attempt accounting and decides whether a failed call should be repeated.

Share one HTTP runner across unary, SSE and batch results. The runner brackets the response and gives endpoint code a reader valid for the duration of its callback. Asynchronous cancellation and caller exceptions unwind that scope. Transport errors, HTTP status failures and decode failures are distinct. Keep provider request IDs and Retry-After values available for callers. Render errors without credentials, headers or response bodies.

# Preserve provider content for assistant replay

Accepted on 2026-11-20.

Decode response blocks into typed observations and retain each provider object for continuation. Replay the original JSON to preserve signed thinking, redacted reasoning, citations and server-tool evidence even as the service adds fields. Use the same decoder for complete messages, stream block starts and successful batch items. Reject malformed fields in known variants and retain unknown tags and their objects.

Keep output observations and request blocks distinct. An application replays assistant history in the originating provider and model scope. The provider or application owns that scope and executes any client tools.

Retain the original JSON beside each validated SSE event so a provider can migrate its HTTP driver before replacing its event assembler. The direct client defaults to API version 2026-10-21. An existing provider can keep its configured version through the JSON bridge. Validate the new version's removed sampling fields before dispatch and keep the provider responsible for model and host compatibility.

Typed Messages, token counting, batch submission and the streaming bridge share envelope validation. They reject empty conversation history on version 2026-10-21 before dispatch. The older contract can use `EmptyConversation` and optional sampling controls. Generation endpoints validate removed sampling fields against the version and token counting projects generation controls out of its body. Model and beta compatibility remain provider policy.

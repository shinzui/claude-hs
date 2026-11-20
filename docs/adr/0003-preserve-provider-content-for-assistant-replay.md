# Preserve provider content for assistant replay

Accepted on 2026-11-20.

Decode response blocks into typed observations and retain each provider object for continuation. Replay the original JSON to preserve signed thinking, redacted reasoning, citations and server-tool evidence even as the service adds fields. Use the same decoder for complete messages, stream block starts and successful batch items. Reject malformed fields in known variants and retain unknown tags and their objects.

Keep output observations and request blocks distinct. An application replays assistant history in the originating provider and model scope. The provider or application owns that scope and executes any client tools.

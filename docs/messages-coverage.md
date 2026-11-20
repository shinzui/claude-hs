# Messages coverage

Wire fixtures use synthetic values sampled from the direct API documentation on 2026-11-20. The default `anthropic-version` is `2026-10-21`. The selected version rejects `temperature`, `top_p` and `top_k` even at their defaults. Audit legacy request builders for those keys before migrating. [API version migration](https://platform.claude.com/docs/en/api/migration-2026-10-21)

- **Synchronous Messages and token counting.** Both accept text and URL or base64 images, structured output configuration, thinking, tools, caching and speed. The count request projects the input fields and excludes the output limit and stop sequences. [Create](https://platform.claude.com/docs/en/api/messages/create), [Count tokens](https://platform.claude.com/docs/en/api/messages/count_tokens)
- **Structured output.** Set `OutputConfig (Just High) (Just schema)` for JSON Schema and independent effort. Read the result with `responseText` and check `stopReason` before decoding it into an application type. A refusal or truncation can leave the result outside the schema. Use document citations in a separate request since the API rejects citations with structured output. [Structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)
- **Strict client tools.** `CustomTool` accepts an input schema and the strict flag. Set tool choice independently. Return results with `InputToolResult` and the original tool ID. Run the tool in the application. [Strict tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/strict-tool-use)
- **Thinking.** `Adaptive` supports summarized, omitted and updates display. Updates requires `thinking-display-updates-2026-08-18`. Manual budgets, disabled mode, between-tools mode and effort values depend on the selected model. Replay original signed blocks, empty signed blocks and redacted blocks in the same provider and model conversation. [Thinking](https://platform.claude.com/docs/en/build-with-claude/thinking)
- **Prompt caching.** Use top-level automatic caching or explicit breakpoints on system blocks, inputs and tools. Breakpoints support default, five-minute and one-hour TTLs. Read creation and read token counts from the response when present. [Prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
- **Citations and web search.** Use `PlainTextDocument` with citations enabled. Returned text exposes character, page, block and web locations. The typed web search tool supports versions `20250305`, `20260209` and `20260318`. Dynamic filtering on later versions is model-dependent. Use `VersionedTool` for other tools or extended options. Output blocks retain unknown tagged values and opaque search evidence. [Citations](https://platform.claude.com/docs/en/build-with-claude/citations), [Web search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool)
- **Fast mode.** Set `speed = Just Fast` for supported models. Supply `fast-mode-2026-02-01` in `RequestOptions` where required. [Fast mode](https://platform.claude.com/docs/en/build-with-claude/fast-mode)

Refresh fixtures by comparing the dated endpoint documentation and migration guide with the captured wire shape. Use synthetic model output, signatures, keys and encrypted citation indices. Compare semantic JSON and run the loopback suite from the locked shell.

**Streaming migration.** `streamMessageValue` accepts a provider-shaped Messages object, validates its model, history and output limit, and owns the stream flag. With `apiVersion = Just "2026-10-21"` it reports removed sampling settings before dispatch. Compatibility callers with a supported old host or model may explicitly configure `Just "2023-06-01"` until they can migrate the setting. The direct client uses `2026-10-21` by default.

**Batch results.** Read JSON Lines with the configured client origin and typed batch ID. The request uses the binary result media type. [Message Batch results](https://platform.claude.com/docs/en/api/messages/batches/results) and [Anthropic Python client](https://github.com/anthropics/anthropic-sdk-python/blob/main/src/anthropic/resources/messages/batches.py)

## Request controls and tools

| Capability | Contract and fixture |
|---|---|
| Empty history and sampling | On `2023-06-01`, construct `EmptyConversation` or set `temperature`, `topP` and `topK` with `withRequestControls` on eligible models. `requestControlsRoundtrip` captures empty SSE and legacy sampling, and verifies independent pre-dispatch rejection on `2026-10-21`. Use `conversationHistory` and `withConversationHistory` with either conversation constructor. |
| Metadata and inference geography | `advancedRequestRoundtrip` captures `metadata` and `inference_geo` on create. |
| Compaction | `Compaction` builds an edit for `compact_20260112`, including instructions, token trigger and pause behavior. Configure the `compact-2026-01-12` beta in request options. `advancedRequestRoundtrip` captures the nested edit. |
| Container reuse | `containerId` places the returned ID on a generation request. `advancedRequestRoundtrip` captures the top-level ID, caller tag and tool ID. |
| Fallback configuration | `DefaultFallbacks` or `FallbackModels` selects server-side fallback with `server-side-fallback-2026-07-01` on eligible models. `advancedRequestRoundtrip` captures the ordered model settings. |
| Mid-conversation system turns | Use `Message System` with text, `ToolAddition` or `ToolRemoval` for eligible models. Tool changes use the `inline-tools-2026-09-15` or platform-specific beta. The fixture captures system role and both reference tags. |
| Deferred tools and tool search | Set `ConfiguredTool` with `ToolLoading` and include a `ToolSearchTool`. The fixture captures both pinned BM25 and regex variants and `defer_loading`. |
| Programmatic tool calling | Supply `CodeExecutionTool` and configure matching `AllowCodeExecution` for compatible client tools. Use the model-supported version of the tool and preserve its caller and container on continuation. |
| Token counting and batches | The count projection drops generation controls and keeps model, messages, system, cache, schema, thinking, speed and tools. Batches embed the synchronous body and use its validation. The fixtures capture both projections and reject removed sampling in batch params on the current version. |
| JSON migration | `MessageRequest` decodes supported serialized requests and preserves tagged input and tool objects. Use `VersionedBlock` and `VersionedTool` for provider extensions. |

See [mid-conversation system messages](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages), [tool search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool), [programmatic tool calling](https://platform.claude.com/docs/en/agents-and-tools/tool-use/programmatic-tool-calling), and [fallback](https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback).

## Response and continuation evidence

| Capability | Representation and fixture |
|---|---|
| Stop evidence | `ModelContextWindowExceeded` and `Refusal` are distinct stop reasons. `StopDetails` retains optional category, explanation and recommended model with an open unknown variant. `unaryEvidence` and `advancedEvidence` exercise create and SSE, and batch success uses the same unary decoder. |
| Billing evidence | `UsageEvidence` includes geography, service tier, speed, output token breakdown, server-tool counters and iterations. `applyUsageUpdate` applies cumulative deltas without clearing missing values. `advancedEvidence` checks an explicit zero and retains unknown server-tool fields and iteration metadata. |
| Programmatic continuation | `continueMessage` reuses the response container and carries ordered server calls, tool search references, code execution results and the programmatic caller into the next request. `advancedContinuation` verifies the exact second POST on `2026-10-21`. |
| Fallback continuation | Send the original model, tool configuration and `server-side-fallback-2026-07-01`. `fallbackContinuation` shows the marker stays in place. The helper retains text and paired server-tool work before a mid-stream fallback, and discards pre-handoff thinking and client calls. |
| Opaque response evidence | `responseJSON`, `blockJSON` and `eventJSON` keep the received provider objects. The documented continuation helper omits unknown block tags. Use `assistantContinuation` or `VersionedBlock` with a provider contract that admits an extension. |
| Error categories | `apiErrorCategory` maps provider error tags to an open enumeration. HTTP status, transport, stream and JSON decode failures keep their existing `ClientError` alternatives. |

The documented tool-search replay includes its result and references. Documented code execution replay can include a completed tool result. The programmatic continuation fixture preserves both, alongside the pending call and container. [Tool search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool), [programmatic tool calling](https://platform.claude.com/docs/en/agents-and-tools/tool-use/programmatic-tool-calling), [fallback](https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback).

For an eligible model, combine the programmatic caller with deferred tool search.
Keep the same tool list on later requests and pass the result of `continueMessage`
to `createMessage` with the original client and request options.

```haskell
import Claude.Messages
import Data.Aeson (Value (String))
import Data.Aeson.KeyMap qualified as KeyMap

lookupFeatures :: MessageFeatures
lookupFeatures =
  defaultMessageFeatures
    { tools =
        [ CodeExecutionTool CodeExecution20260120 Nothing,
          ToolSearchTool BM25Search20251119 Nothing,
          ConfiguredTool
            (ClientTool "lookup" (Just "Look up a catalog entry") schema Nothing Nothing)
            (ToolLoading (Just True) (Just [AllowDirect, AllowCodeExecution CodeExecution20260120]))
        ]
    }
  where
    schema = KeyMap.singleton "type" (String "object")
```

For unary prompt cache pre-warming, use `cacheOnly` as the output limit and
copy the prompt and cache settings from the generation request. The
`cachePrewarm` fixture verifies a zero-token unary body and pre-dispatch
rejection of the same limit for streams and batches. [Prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)

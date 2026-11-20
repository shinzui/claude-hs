module FeaturesSpec (run, enrichedConversation, enrichedOptions, thinkingBlock, redactedBlock, webCitation) where

import Claude.Client
import Claude.Messages
import Control.Lens ((^.))
import Data.Aeson (Key, Object, Value (..), object, toJSON, (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Generics.Labels ()
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import MessagesSpec (baseConversation, messageFixture, sampleRequest)
import Network.HTTP.Types (status200)
import Network.Wai qualified as Wai
import Support.Server

schemaFixture :: Object
schemaFixture = KeyMap.fromList ["type" .= ("object" :: Text), "additionalProperties" .= False]

toolFixture :: Tool
toolFixture = CustomTool (ClientTool "lookup" (Just "Look up a color") schemaFixture (Just True) (Just (Ephemeral (Just FiveMinutes))))

enrichedConversation :: Conversation
enrichedConversation =
  baseConversation
    { system = Just (SystemBlocks [SystemBlock "Cite the supplied material." (Just (Ephemeral (Just OneHour)))]),
      features =
        defaultMessageFeatures
          { thinking = Just (Adaptive (Just Omitted)),
            cacheControl = Just (Ephemeral Nothing),
            tools = [toolFixture],
            toolChoice = Just (AutoTool True),
            speed = Just Fast
          }
    }

enrichedOptions :: RequestOptions
enrichedOptions = defaultRequestOptions {betaFeatures = ["fast-mode-2026-02-01"]}

thinkingBlock :: Text -> Text -> Value
thinkingBlock summary signature =
  object ["type" .= ("thinking" :: Text), "thinking" .= summary, "signature" .= signature, "provider_state" .= True]

redactedBlock :: Value
redactedBlock = object ["type" .= ("redacted_thinking" :: Text), "data" .= ("ciphertext" :: Text)]

toolUseBlock :: Text -> Value
toolUseBlock toolId =
  object ["type" .= ("tool_use" :: Text), "id" .= toolId, "name" .= ("lookup" :: Text), "input" .= object []]

run :: IO ()
run = do
  schemaAndToolIndependence
  consecutiveToolRounds
  citationsAndSearch
  malformedKnownBlock
  putStrLn "Features: structured output, tool continuation, cache and citation fixtures passed"

schemaAndToolIndependence :: IO ()
schemaAndToolIndependence = do
  let schema = OutputConfig (Just High) (Just schemaFixture)
      schemaConvo = baseConversation {features = defaultMessageFeatures {outputConfig = Just schema}}
      toolConvo = baseConversation {features = defaultMessageFeatures {tools = [toolFixture], toolChoice = Just (NamedTool "lookup" False)}}
      bothConvo = enrichedConversation {features = (enrichedConversation ^. #features) {outputConfig = Just schema}}
  schemaRequest <- sampleRequest schemaConvo
  toolsRequest <- sampleRequest toolConvo
  bothRequest <- sampleRequest bothConvo
  let expectedOutput =
        object
          [ "effort" .= ("high" :: Text),
            "format" .= object ["type" .= ("json_schema" :: Text), "schema" .= schemaFixture]
          ]
      expectedTool =
        object
          [ "name" .= ("lookup" :: Text),
            "description" .= ("Look up a color" :: Text),
            "input_schema" .= schemaFixture,
            "strict" .= True,
            "cache_control" .= object ["type" .= ("ephemeral" :: Text), "ttl" .= ("5m" :: Text)]
          ]
      app req send = do
        body <- requestJson req
        let check expected key = assertEqual "request field" expected (field key body)
        case lookup "x-case" (Wai.requestHeaders req) of
          Just "schema" -> do
            check (Just expectedOutput) "output_config"
            check Nothing "tools"
            check Nothing "tool_choice"
          Just "count" -> do
            assertEqual "count path" "/v1/messages/count_tokens" (Wai.rawPathInfo req)
            check (Just expectedOutput) "output_config"
            check Nothing "max_tokens"
          Just "tool" -> do
            check Nothing "output_config"
            check (Just (toJSON [expectedTool])) "tools"
            check (Just (object ["type" .= ("tool" :: Text), "name" .= ("lookup" :: Text)])) "tool_choice"
          Just "both" -> do
            check (Just expectedOutput) "output_config"
            check (Just (toJSON [expectedTool])) "tools"
            check (Just (toJSON Fast)) "speed"
            assertEqual "fast-mode beta" (Just "fast-mode-2026-02-01") (lookup "anthropic-beta" (Wai.requestHeaders req))
          _ -> fail "Unknown fixture"
        if Wai.rawPathInfo req == "/v1/messages/count_tokens"
          then send (json status200 [] (object ["input_tokens" .= (17 :: Int)]))
          else send (json status200 [] (putField "stop_reason" "refusal" (messageFixture [textBlock "{\"ok\":true}" []])))
  withClient app $ \client -> do
    let options tag = enrichedOptions {extraHeaders = [("x-case", tag)]}
    Response _ refused <- createMessage client (options "schema") schemaRequest >>= expectRight
    assertEqual "refusal remains a successful HTTP response" (Just Refusal) (refused ^. #stopReason)
    assertEqual "structured output text" "{\"ok\":true}" (responseText refused)
    _ <- createMessage client (options "tool") toolsRequest >>= expectRight
    _ <- createMessage client (options "both") bothRequest >>= expectRight
    Response _ counted <- countTokens client (options "count") (CountRequest schemaConvo) >>= expectRight
    assertEqual "count with schema" (TokenCount 17) counted

consecutiveToolRounds :: IO ()
consecutiveToolRounds = do
  call <- newIORef (0 :: Int)
  request <- sampleRequest enrichedConversation
  let first = [thinkingBlock "" "signature-1", toolUseBlock "toolu_1"]
      second = [thinkingBlock "visible" "signature-2", redactedBlock, toolUseBlock "toolu_2"]
      historyPrefix = conversationHistory enrichedConversation
      toolReply toolId = Message User (InputToolResult (ToolResult toolId (ToolResultText "green") Nothing Nothing) :| [])
      resultJson toolId =
        object
          [ "role" .= ("user" :: Text),
            "content" .= [object ["type" .= ("tool_result" :: Text), "tool_use_id" .= toolId, "content" .= ("green" :: Text)]]
          ]
      historyWith blocks toolId =
        [object ["role" .= ("assistant" :: Text), "content" .= blocks], resultJson (toolId :: Text)]
      expectedHistory = map toJSON (historyPrefix)
      app req send = do
        number <- atomicModifyIORef' call (\n -> (n + 1, n))
        body <- requestJson req
        assertEqual "adaptive omitted display" (Just (object ["type" .= ("adaptive" :: Text), "display" .= ("omitted" :: Text)])) (field "thinking" body)
        assertEqual
          "cached system"
          ( Just
              ( toJSON
                  [ object
                      [ "type" .= ("text" :: Text),
                        "text" .= ("Cite the supplied material." :: Text),
                        "cache_control" .= object ["type" .= ("ephemeral" :: Text), "ttl" .= ("1h" :: Text)]
                      ]
                  ]
              )
          )
          (field "system" body)
        assertEqual "automatic cache" (Just (object ["type" .= ("ephemeral" :: Text)])) (field "cache_control" body)
        let respond blocks = send (json status200 [] (putField "stop_reason" "tool_use" (messageFixture blocks)))
        case number of
          0 -> respond first
          1 -> do
            assertEqual "first continuation" (Just (toJSON (expectedHistory <> historyWith first "toolu_1"))) (field "messages" body)
            respond second
          _ -> do
            assertEqual "two consecutive continuations" (Just (toJSON (expectedHistory <> historyWith first "toolu_1" <> historyWith second "toolu_2"))) (field "messages" body)
            send (json status200 [] (messageFixture [textBlock "green" []]))
      go client history = do
        let updated = request {conversation = withConversationHistory history enrichedConversation}
        Response _ result <- createMessage client enrichedOptions updated >>= expectRight
        pure result
  withClient app $ \client -> do
    firstResponse <- go client historyPrefix
    firstAssistant <- maybe (fail "missing first continuation") pure (assistantContinuation firstResponse)
    let secondHistory = historyPrefix <> [firstAssistant, toolReply "toolu_1"]
    secondResponse <- go client secondHistory
    secondAssistant <- maybe (fail "missing second continuation") pure (assistantContinuation secondResponse)
    lastResponse <- go client (secondHistory <> [secondAssistant, toolReply "toolu_2"])
    assertEqual "two-tool continuation result" "green" (responseText lastResponse)
  readIORef call >>= assertEqual "tool-round dispatch count" 3
  assertEqual
    "manual thinking budget"
    (object ["type" .= ("enabled" :: Text), "budget_tokens" .= (1024 :: Int)])
    (toJSON (ManualBudget 1024 Nothing))
  assertEqual "thinking disabled" (object ["type" .= ("disabled" :: Text)]) (toJSON ThinkingDisabled)

webCitation :: Value
webCitation =
  object
    [ "type" .= ("web_search_result_location" :: Text),
      "cited_text" .= ("forest" :: Text),
      "url" .= ("https://example.test/report" :: Text),
      "title" .= ("Report" :: Text),
      "encrypted_index" .= ("encrypted-index" :: Text)
    ]

citationsAndSearch :: IO ()
citationsAndSearch = do
  let citation =
        object
          [ "type" .= ("char_location" :: Text),
            "cited_text" .= ("forest" :: Text),
            "document_index" .= (0 :: Int),
            "document_title" .= ("Report" :: Text),
            "start_char_index" .= (2 :: Int),
            "end_char_index" .= (8 :: Int)
          ]
      searchHit =
        object
          [ "type" .= ("web_search_result" :: Text),
            "url" .= ("https://example.test/report" :: Text),
            "title" .= ("Report" :: Text),
            "encrypted_content" .= ("encrypted-hit" :: Text),
            "page_age" .= ("today" :: Text)
          ]
      searchCall =
        object
          [ "type" .= ("server_tool_use" :: Text),
            "id" .= ("srvtoolu_1" :: Text),
            "name" .= ("web_search" :: Text),
            "input" .= object ["query" .= ("forests" :: Text)]
          ]
      searchResult = object ["type" .= ("web_search_tool_result" :: Text), "tool_use_id" .= ("srvtoolu_1" :: Text), "content" .= [searchHit]]
      searchError =
        object
          [ "type" .= ("web_search_tool_result" :: Text),
            "tool_use_id" .= ("srvtoolu_2" :: Text),
            "content" .= object ["type" .= ("web_search_tool_result_error" :: Text), "error_code" .= ("overloaded" :: Text)]
          ]
      future = object ["type" .= ("future_tool_result" :: Text), "content" .= True]
      blocks = [searchCall, searchResult, searchError, textBlock "document" [citation], textBlock "web" [webCitation], future]
      document = PlainTextDocument "A forest" (Just "Report") Nothing True Nothing
      convo =
        (withConversationHistory [Message User (InputDocument document :| [])] baseConversation)
          { features = defaultMessageFeatures {tools = [WebSearchTool (WebSearch WebSearch20250305 (Just 2) Nothing)]}
          }
      reply =
        putField
          "usage"
          ( object
              [ "input_tokens" .= (17 :: Int),
                "output_tokens" .= (8 :: Int),
                "cache_creation_input_tokens" .= (4 :: Int),
                "cache_read_input_tokens" .= (6 :: Int)
              ]
          )
          (messageFixture blocks)
      app req send = do
        body <- requestJson req
        assertEqual "versioned web search" (Just (toJSON [object ["type" .= ("web_search_20250305" :: Text), "name" .= ("web_search" :: Text), "max_uses" .= (2 :: Int)]])) (field "tools" body)
        case lookup "x-case" (Wai.requestHeaders req) of
          Just "replay" -> do
            let expected = object ["role" .= ("assistant" :: Text), "content" .= blocks]
            assert "assistant evidence in replay" (maybe False (contains expected) (field "messages" body))
          _ -> assertEqual "document and enabled citations" (Just (toJSON (conversationHistory convo))) (field "messages" body)
        send (json status200 [] reply)
  request <- sampleRequest convo
  withClient app $ \client -> do
    Response _ result <- createMessage client defaultRequestOptions request >>= expectRight
    let counters = result ^. #usage
    assertEqual "cache counters" (Just 4, Just 6) (counters ^. #cacheCreationInputTokens, counters ^. #cacheReadInputTokens)
    case map blockContent (result ^. #content) of
      [ ServerToolUse "srvtoolu_1" "web_search" _,
        WebSearchToolResult "srvtoolu_1" (WebSearchResults [SearchResult _ _ "encrypted-hit" (Just "today")]),
        WebSearchToolResult "srvtoolu_2" (WebSearchError "overloaded"),
        OutputText "document" (Just [Citation (CharacterRange "forest" 0 (Just "Report") 2 8) _]),
        OutputText "web" (Just [Citation (WebLocation "forest" "https://example.test/report" (Just "Report") "encrypted-index") _]),
        UnknownBlock "future_tool_result"
        ] -> pure ()
      _ -> fail "Expected typed document, web and future response blocks"
    resumed <- maybe (fail "missing search continuation") pure (assistantContinuation result)
    let replay = request {conversation = withConversationHistory (conversationHistory convo <> [resumed, Message User (InputText "Summarize" :| [])]) convo}
    _ <- createMessage client (defaultRequestOptions {extraHeaders = [("x-case", "replay")]}) replay >>= expectRight
    pure ()
  where
    contains needle (Array fields) = needle `elem` fields
    contains _ _ = False

malformedKnownBlock :: IO ()
malformedKnownBlock = do
  request <- sampleRequest baseConversation
  let malformed = object ["type" .= ("thinking" :: Text), "thinking" .= ("" :: Text)]
      app _ send = send (json status200 [] (messageFixture [malformed]))
  withClient app $ \client ->
    createMessage client defaultRequestOptions request >>= \case
      Left (DecodeError _ _) -> pure ()
      _ -> fail "Missing signature should produce a decode error"

textBlock :: Text -> [Value] -> Value
textBlock body cites = object ["type" .= ("text" :: Text), "text" .= body, "citations" .= cites]

field :: Key -> Value -> Maybe Value
field key (Object o) = KeyMap.lookup key o
field _ _ = Nothing

putField :: Key -> Value -> Value -> Value
putField key item (Object o) = Object (KeyMap.insert key item o)
putField _ _ raw = raw

module MessagesSpec (run, baseConversation, messageFixture, messageWithEvidence, sampleRequest) where

import Claude.Batches (BatchItem (..), createBatch, mkCustomId)
import Claude.Client
import Claude.Messages
import Claude.Streaming qualified as Claude
import Control.Lens ((^.))
import Control.Monad (void, when)
import Data.Aeson (Key, Value (..), eitherDecode, encode, object, toJSON, (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Pair)
import Data.Generics.Labels ()
import Data.IORef (atomicModifyIORef', modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Network.HTTP.Types (status200, status302, status429, status502)
import Network.Wai qualified as Wai
import Support.Server

baseConversation :: Conversation
baseConversation = Conversation "candidate-model" (Message User (InputText "Hello" :| []) :| []) Nothing defaultMessageFeatures

sampleRequest :: Conversation -> IO MessageRequest
sampleRequest convo = maybe (fail "internal fixture limit") (\limit -> pure (MessageRequest convo limit [])) (maxTokens 256)

messageFixture :: [Value] -> Value
messageFixture blocks =
  object
    [ "id" .= ("msg_1" :: Text),
      "type" .= ("message" :: Text),
      "model" .= ("candidate-model" :: Text),
      "role" .= ("assistant" :: Text),
      "content" .= blocks,
      "stop_reason" .= ("end_turn" :: Text),
      "stop_sequence" .= (Nothing :: Maybe Text),
      "usage" .= object ["input_tokens" .= (17 :: Int), "output_tokens" .= (8 :: Int)]
    ]

run :: IO ()
run = do
  textRoundtrip
  tokensRoundtrip
  failureCases
  requestControlsRoundtrip
  advancedRequestRoundtrip
  advancedContinuation
  fallbackContinuation
  unaryEvidence
  putStrLn "Messages: text, session headers, token count and failure fixtures passed"

textRoundtrip :: IO ()
textRoundtrip = do
  request <- sampleRequest baseConversation
  let future = object ["type" .= ("future" :: Text), "state" .= True]
      options = defaultRequestOptions {betaFeatures = ["beta-one", "beta-two"], extraHeaders = [("x-session-affinity", "session-7")]}
      app req send = do
        assertEqual "method" "POST" (Wai.requestMethod req)
        assertEqual "path" "/v1/messages" (Wai.rawPathInfo req)
        assertEqual "key" (Just "loopback-secret") (lookup "x-api-key" (Wai.requestHeaders req))
        assertEqual "version" (Just "2026-10-21") (lookup "anthropic-version" (Wai.requestHeaders req))
        assertEqual "betas" (Just "beta-one,beta-two") (lookup "anthropic-beta" (Wai.requestHeaders req))
        assertEqual "session affinity" (Just "session-7") (lookup "x-session-affinity" (Wai.requestHeaders req))
        requestJson req
          >>= assertEqual
            "body"
            ( object
                [ "model" .= ("candidate-model" :: Text),
                  "max_tokens" .= (256 :: Int),
                  "messages"
                    .= [ object
                           [ "role" .= ("user" :: Text),
                             "content" .= [object ["type" .= ("text" :: Text), "text" .= ("Hello" :: Text)]]
                           ]
                       ]
                ]
            )
        send (json status200 [("request-id", "req_1")] (messageFixture [object ["type" .= ("text" :: Text), "text" .= ("Hi" :: Text)], future]))
  withClient app $ \client -> do
    Response meta response <- createMessage client options request >>= expectRight
    assertEqual "request ID" (Just "req_1") (requestId meta)
    let MessageResponse messageId modelId sender blocks reason matchedStop counters _ _ _ = response
    assertEqual "typed message metadata" ("msg_1", "candidate-model", Assistant, Just EndTurn, Nothing, Usage 17 8 Nothing Nothing Nothing Nothing (UsageEvidence Nothing Nothing Nothing Nothing Nothing Nothing)) (messageId, modelId, sender, reason, matchedStop, counters)
    assertEqual "typed blocks" [OutputText "Hi" Nothing, UnknownBlock "future"] (map blockContent blocks)
    assertEqual "unknown block payload" [future] (drop 1 (map blockJSON blocks))
    createMessage client (options {extraHeaders = [("HOST", "wrong-host")]}) request >>= \case
      Left (InvalidRequest _) -> pure ()
      _ -> fail "Host override must be rejected"

tokensRoundtrip :: IO ()
tokensRoundtrip = do
  let history =
        Message User (InputText "First" :| [])
          :| [ Message Assistant (InputText "Welcome" :| []),
               Message User (InputImage (Base64Image "image/png" "aW1hZ2U=") :| [InputImage (ImageUrl "https://example.test/image.png")])
             ]
      convo = Conversation "candidate-model" history (Just (SystemText "Use the image.")) defaultMessageFeatures
      app req send = do
        assertEqual "count method" "POST" (Wai.requestMethod req)
        assertEqual "count path" "/v1/messages/count_tokens" (Wai.rawPathInfo req)
        requestJson req
          >>= assertEqual
            "count body"
            ( object
                [ "model" .= ("candidate-model" :: Text),
                  "messages"
                    .= [ turn "user" [text "First"],
                         turn "assistant" [text "Welcome"],
                         turn
                           "user"
                           [ image ["type" .= ("base64" :: Text), "media_type" .= ("image/png" :: Text), "data" .= ("aW1hZ2U=" :: Text)],
                             image ["type" .= ("url" :: Text), "url" .= ("https://example.test/image.png" :: Text)]
                           ]
                       ],
                  "system" .= ("Use the image." :: Text)
                ]
            )
        send (json status200 [] (object ["input_tokens" .= (17 :: Int)]))
  withClient app $ \client -> do
    Response _ result <- countTokens client defaultRequestOptions (CountRequest convo) >>= expectRight
    assertEqual "input tokens" (TokenCount 17) result
  where
    text body = object ["type" .= ("text" :: Text), "text" .= (body :: Text)]
    image source = object ["type" .= ("image" :: Text), "source" .= object source]

failureCases :: IO ()
failureCases = do
  request <- sampleRequest baseConversation
  calls <- newIORef (0 :: Int)
  let app req send = do
        _ <- Wai.strictRequestBody req
        modifyIORef' calls (+ 1)
        case lookup "x-fixture" (Wai.requestHeaders req) of
          Just "rate-limit" ->
            send
              ( json
                  status429
                  [("request-id", "req_rate"), ("retry-after", "3")]
                  ( object
                      ["error" .= object ["type" .= ("rate_limit_error" :: Text), "message" .= ("Echo loopback-secret" :: Text)]]
                  )
              )
          Just "invalid-json" -> send (Wai.responseLBS status200 [("request-id", "req_decode")] "invalid")
          Just "redirect" -> send (Wai.responseLBS status302 [("location", "/other-origin")] "")
          Just "disconnect" -> send (Wai.responseRaw (\_ _ -> pure ()) (Wai.responseLBS status502 [] ""))
          _ -> send (Wai.responseLBS status502 [] "Bad gateway")
  withClient app $ \client -> do
    let call fixture = createMessage client (defaultRequestOptions {extraHeaders = [("x-fixture", fixture)]}) request
    call "rate-limit" >>= \case
      Left err@(ApiStatusError meta (Just (ApiError "rate_limit_error" detail)) excerpt) -> do
        assertEqual "retry metadata" (Just "req_rate", Just "3", 429) (requestId meta, retryAfter meta, status meta)
        assert "redacted HTTP body" (not ("loopback-secret" `Text.isInfixOf` excerpt))
        assertEqual "redacted detail" "Echo [redacted]" detail
        assert "secret absent from Show" (not ("loopback-secret" `isInfixOf` show err))
      _ -> fail "Expected structured rate limit"
    call "gateway" >>= \case
      Left (ApiStatusError (ResponseMetadata Nothing Nothing 502 _ _ _) Nothing "Bad gateway") -> pure ()
      _ -> fail "Expected non-JSON status error"
    call "invalid-json" >>= \case
      Left (DecodeError (ResponseMetadata (Just "req_decode") Nothing 200 _ _ _) _) -> pure ()
      _ -> fail "Expected JSON decode failure"
    call "redirect" >>= \case
      Left (ApiStatusError (ResponseMetadata _ _ 302 _ _ _) Nothing _) -> pure ()
      _ -> fail "Expected redirect to be returned as HTTP failure"
    call "disconnect" >>= \case
      Left (TransportError _ Disconnected) -> pure ()
      Left err -> fail ("Expected disconnected request, got " <> show err)
      Right _ -> fail "Disconnected request succeeded"
  readIORef calls >>= assertEqual "one dispatch per operation" 5

requestControlsRoundtrip :: IO ()
requestControlsRoundtrip = do
  empty <- sampleRequest (EmptyConversation "claude-sonnet-4-6" Nothing defaultMessageFeatures)
  filled <- sampleRequest (Conversation "claude-sonnet-4-6" (Message User (InputText "Hello" :| []) :| []) Nothing defaultMessageFeatures)
  let tuning = defaultRequestControls {temperature = Just 0.2, topP = Just 0.7, topK = Just 15}
      emptyJSON = object ["model" .= ("claude-sonnet-4-6" :: Text), "max_tokens" .= (256 :: Int), "messages" .= ([] :: [Value]), "stream" .= True]
      samplingJSON = object ["model" .= ("claude-sonnet-4-6" :: Text), "max_tokens" .= (256 :: Int), "messages" .= [userHello], "temperature" .= (0.2 :: Double), "top_p" .= (0.7 :: Double), "top_k" .= (15 :: Int)]
      legacy = (defaultClientConfig "loopback-secret") {apiVersion = Just "2023-06-01"}
      opts = defaultRequestOptions
  withClientConfig legacy (capture emptyJSON sseStop) $ \client ->
    void $ Claude.streamMessage client opts empty (\_ _ -> pure Claude.Continue) >>= expectRight
  withClientConfig legacy (capture samplingJSON (json status200 [] (messageFixture []))) $ \client ->
    void $ createMessage client opts (withRequestControls tuning filled) >>= expectRight
  calls <- newIORef (0 :: Int)
  withClient (\_ send -> modifyIORef' calls (+ 1) >> send sseStop) $ \client -> do
    invalid "nonempty" =<< Claude.streamMessage client opts empty (\_ _ -> pure Claude.Continue)
    invalid "sampling" =<< Claude.streamMessage client opts (withRequestControls tuning filled) (\_ _ -> pure Claude.Continue)
    invalid "sampling" =<< createMessage client opts (withRequestControls tuning filled)
    invalid "nonempty" =<< countTokens client opts (CountRequest (conversation empty))
    ident <- maybe (fail "invalid test ID") pure (mkCustomId "example")
    invalid "sampling" =<< createBatch client opts (BatchItem ident (withRequestControls tuning filled) :| [])
  readIORef calls >>= assertEqual "invalid requests never dispatched" 0
  where
    invalid fragment = \case
      Left (InvalidRequest detail) -> assert "validation detail" (fragment `Text.isInfixOf` detail)
      _ -> fail "expected InvalidRequest"

advancedRequestRoundtrip :: IO ()
advancedRequestRoundtrip = do
  let schema = KeyMap.fromList ["type" .= ("object" :: Text)]
      tool = ClientTool "lookup" Nothing schema Nothing Nothing
      toolFeatures =
        defaultMessageFeatures
          { tools = [CodeExecutionTool CodeExecution20250825 Nothing, ToolSearchTool BM25Search20251119 Nothing, ToolSearchTool RegexSearch20251119 Nothing, ConfiguredTool tool (ToolLoading (Just True) (Just [AllowDirect, AllowCodeExecution CodeExecution20250825])), CustomTool (ClientTool "old_lookup" Nothing schema Nothing Nothing)]
          }
      toolCall = InputToolUse "toolu_1" "lookup" (object []) (Just (CodeExecutionCaller CodeExecution20250825 "srvtoolu_1"))
      systemChange = Message System (ToolAddition (ToolReference "lookup") Nothing :| [ToolRemoval (ToolReference "old_lookup") Nothing])
      convo = Conversation "claude-opus-4-8" (Message User (InputText "Hello" :| []) :| [systemChange, Message Assistant (toolCall :| []), Message User (InputToolResult (ToolResult "toolu_1" (ToolResultText "result") Nothing Nothing) :| [])]) Nothing toolFeatures
      controls =
        defaultRequestControls
          { containerId = Just "container_1",
            metadata = Just (Map.singleton "user_id" "user_1"),
            contextManagement = Just [Compaction (Just "Keep names") (Just True) (Just 100000)],
            inferenceGeo = Just "us",
            fallbacks = Just (FallbackModels [FallbackModel "claude-sonnet-4-6" (Just 128) Nothing Nothing Nothing])
          }
      opts = defaultRequestOptions {betaFeatures = ["inline-tools-2026-09-15", "compact-2026-01-12", "server-side-fallback-2026-07-01"]}
      history =
        [ userHello,
          turn "system" [tagged "tool_addition" ["tool" .= tagged "tool_reference" ["name" .= ("lookup" :: Text)]], tagged "tool_removal" ["tool" .= tagged "tool_reference" ["name" .= ("old_lookup" :: Text)]]],
          turn "assistant" [tagged "tool_use" ["id" .= ("toolu_1" :: Text), "name" .= ("lookup" :: Text), "input" .= object [], "caller" .= tagged "code_execution_20250825" ["tool_id" .= ("srvtoolu_1" :: Text)]]],
          turn "user" [tagged "tool_result" ["tool_use_id" .= ("toolu_1" :: Text), "content" .= ("result" :: Text)]]
        ]
      toolsJSON =
        [ tagged "code_execution_20250825" ["name" .= ("code_execution" :: Text)],
          tagged "tool_search_tool_bm25_20251119" ["name" .= ("tool_search_tool_bm25" :: Text)],
          tagged "tool_search_tool_regex_20251119" ["name" .= ("tool_search_tool_regex" :: Text)],
          object ["name" .= ("lookup" :: Text), "input_schema" .= object ["type" .= ("object" :: Text)], "defer_loading" .= True, "allowed_callers" .= (["direct", "code_execution_20250825"] :: [Text])],
          object ["name" .= ("old_lookup" :: Text), "input_schema" .= object ["type" .= ("object" :: Text)]]
        ]
      promptFields = ["model" .= ("claude-opus-4-8" :: Text), "messages" .= history, "tools" .= toolsJSON]
      expected =
        object $
          promptFields
            <> [ "max_tokens" .= (256 :: Int),
                 "stop_sequences" .= (["done"] :: [Text]),
                 "container" .= ("container_1" :: Text),
                 "metadata" .= object ["user_id" .= ("user_1" :: Text)],
                 "context_management" .= object ["edits" .= [tagged "compact_20260112" ["instructions" .= ("Keep names" :: Text), "pause_after_compaction" .= True, "trigger" .= tagged "input_tokens" ["value" .= (100000 :: Int)]]]],
                 "inference_geo" .= ("us" :: Text),
                 "fallbacks" .= [object ["model" .= ("claude-sonnet-4-6" :: Text), "max_tokens" .= (128 :: Int)]]
               ]
      app req send = do
        assertEqual "advanced beta header" (Just "inline-tools-2026-09-15,compact-2026-01-12,server-side-fallback-2026-07-01") (lookup "anthropic-beta" (Wai.requestHeaders req))
        case Wai.rawPathInfo req of
          "/v1/messages" -> capture expected (json status200 [] (messageFixture [])) req send
          "/v1/messages/count_tokens" -> capture (object promptFields) (json status200 [] (object ["input_tokens" .= (10 :: Int)])) req send
          _ -> fail "unexpected request route"
  base <- sampleRequest convo
  let request = withRequestControls controls base {stopSequences = ["done"]}
  withClient app $ \client -> do
    _ <- createMessage client opts request >>= expectRight
    void $ countTokens client opts (CountRequest convo) >>= expectRight
  decoded <- expectRight (eitherDecode (encode expected))
  assertEqual "advanced request JSON decode and re-encode" expected (toJSON (decoded :: MessageRequest))

capture :: Value -> Wai.Response -> Wai.Application
capture expected reply req send = requestJson req >>= assertEqual "captured request" expected >> send reply

sseStop :: Wai.Response
sseStop = Wai.responseLBS status200 [("content-type", "text/event-stream")] "data: {\"type\":\"message_stop\"}\n\n"

turn :: Text -> [Value] -> Value
turn sender blocks = object ["role" .= sender, "content" .= blocks]

tagged :: Text -> [Pair] -> Value
tagged tag fields = object (("type" .= tag) : fields)

userHello :: Value
userHello = turn "user" [tagged "text" ["text" .= ("Hello" :: Text)]]

advancedContinuation :: IO ()
advancedContinuation = do
  let schema = KeyMap.singleton "type" (String "object")
      features_ =
        defaultMessageFeatures
          { tools =
              [ ToolSearchTool BM25Search20251119 Nothing,
                CodeExecutionTool CodeExecution20260120 Nothing,
                ConfiguredTool (ClientTool "lookup" Nothing schema Nothing Nothing) (ToolLoading (Just True) (Just [AllowDirect, AllowCodeExecution CodeExecution20260120]))
              ]
          }
      serverCall ident name_ = tagged "server_tool_use" ["id" .= (ident :: Text), "name" .= (name_ :: Text), "input" .= object []]
      search =
        tagged
          "tool_search_tool_result"
          ["tool_use_id" .= ("srvtoolu_search" :: Text), "content" .= tagged "tool_search_tool_search_result" ["tool_references" .= [tagged "tool_reference" ["tool_name" .= ("lookup" :: Text)]]]]
      code =
        tagged
          "code_execution_tool_result"
          ["tool_use_id" .= ("srvtoolu_done" :: Text), "content" .= tagged "code_execution_result" ["stdout" .= ("done" :: Text), "stderr" .= ("" :: Text), "return_code" .= (0 :: Int), "content" .= ([] :: [Value])]]
      tool =
        tagged
          "tool_use"
          [ "id" .= ("toolu_1" :: Text),
            "name" .= ("lookup" :: Text),
            "input" .= object [],
            "caller" .= tagged "code_execution_20260120" ["tool_id" .= ("srvtoolu_pending" :: Text), "future_caller_field" .= True],
            "future_tool_field" .= (1 :: Int)
          ]
      unknown = tagged "future_only" ["passed_through" .= True]
      knownBlocks = [serverCall "srvtoolu_search" "tool_search_tool_bm25", search, serverCall "srvtoolu_done" "code_execution", code, serverCall "srvtoolu_pending" "code_execution", tool]
      blocks = knownBlocks <> [unknown]
      toolResult = InputToolResult (ToolResult "toolu_1" (ToolResultText "result") Nothing Nothing)
      resultJson = tagged "tool_result" ["tool_use_id" .= ("toolu_1" :: Text), "content" .= ("result" :: Text)]
      container_ = object ["id" .= ("container_1" :: Text), "expires_at" .= ("2026-11-20T23:30:00Z" :: Text)]
      fixture = addField "container" container_ $ addField "stop_reason" "tool_use" $ messageFixture blocks
      conversation_ = Conversation "claude-opus-5-5" (Message User (InputText "Hello" :| []) :| []) Nothing features_
      opts = defaultRequestOptions
  request <- sampleRequest conversation_
  twoTurns opts request fixture (toolResult :| []) $ \initial result outgoing -> do
    assertEqual "exact opaque provider observations" fixture (toJSON result)
    case map blockContent (result ^. #content) of
      [ServerToolUse {}, OutputToolSearchResult _ (ToolSearchMatches ["lookup"]), ServerToolUse {}, OutputCodeExecutionResult _ (CodeExecutionCompleted "done" "" 0 []), ServerToolUse {}, OutputToolUseWithCaller "toolu_1" "lookup" _ (CodeExecutionCaller CodeExecution20260120 "srvtoolu_pending"), UnknownBlock "future_only"] -> pure ()
      _ -> fail "missing typed continuation evidence"
    assertEqual
      "second request history and container"
      (addField "container" "container_1" (addField "messages" (toJSON [userHello, turn "assistant" knownBlocks, turn "user" [resultJson]]) initial))
      outgoing

fallbackContinuation :: IO ()
fallbackContinuation = do
  let textBlock body = tagged "text" ["text" .= (body :: Text)]
      marker =
        tagged
          "fallback"
          [ "from" .= object ["model" .= ("claude-fable-5" :: Text)],
            "to" .= object ["model" .= ("claude-opus-4-8" :: Text)],
            "trigger" .= tagged "refusal" ["category" .= ("other" :: Text)]
          ]
      suffix = textBlock "Fallback text"
      fixture = addField "model" "claude-opus-4-8" (messageFixture [marker, suffix])
      opts = defaultRequestOptions {betaFeatures = ["server-side-fallback-2026-07-01"]}
      conversation_ = Conversation "claude-fable-5" (Message User (InputText "Hello" :| []) :| []) Nothing defaultMessageFeatures
  request <- withRequestControls defaultRequestControls {fallbacks = Just DefaultFallbacks} <$> sampleRequest conversation_
  let explicit = Message Assistant (InputFallback (FallbackMarker "claude-fable-5" "claude-opus-4-8" "refusal" (Just "other")) :| [InputText "Fallback text"])
  assertEqual "typed fallback history" (turn "assistant" [marker, suffix]) (toJSON explicit)
  twoTurns opts request fixture (InputText "Continue" :| []) $ \initial result outgoing -> do
    case map blockContent (result ^. #content) of
      [OutputFallback (FallbackMarker "claude-fable-5" "claude-opus-4-8" "refusal" (Just "other")), OutputText {}] -> pure ()
      _ -> fail "missing fallback identity"
    assertEqual
      "fallback keeps model, settings and marker order"
      (addField "messages" (toJSON [userHello, turn "assistant" [marker, suffix], turn "user" [textBlock "Continue"]]) initial)
      outgoing

twoTurns ::
  RequestOptions ->
  MessageRequest ->
  Value ->
  NonEmpty InputBlock ->
  (Value -> MessageResponse -> Value -> IO ()) ->
  IO ()
twoTurns options request fixture followUp check = do
  requests <- newIORef []
  let app req send = do
        assertEqual "continuation version" (Just "2026-10-21") (lookup "anthropic-version" (Wai.requestHeaders req))
        when (not (null (betaFeatures options))) $
          assertEqual "fallback beta" (Just "server-side-fallback-2026-07-01") (lookup "anthropic-beta" (Wai.requestHeaders req))
        body <- requestJson req
        subsequent <- atomicModifyIORef' requests (\prior -> (prior <> [body], not (null prior)))
        send (json status200 [] (if subsequent then messageFixture [] else fixture))
  withClient app $ \client -> do
    Response _ decoded <- createMessage client options request >>= expectRight
    next <- maybe (fail "missing continuation") pure (continueMessage request decoded followUp)
    _ <- createMessage client options next >>= expectRight
    readIORef requests >>= \case
      [initial, outgoing] -> check initial decoded outgoing
      _ -> fail "expected exactly two requests"

addField :: Key -> Value -> Value -> Value
addField key value (Object fields) = Object (KeyMap.insert key value fields)
addField _ _ value = value

messageWithEvidence :: Value
messageWithEvidence =
  addField "stop_reason" "refusal" $
    addField "stop_details" (tagged "refusal" ["category" .= ("other" :: Text), "explanation" .= ("declined" :: Text)]) $
      addField
        "usage"
        ( object
            [ "input_tokens" .= (17 :: Int),
              "output_tokens" .= (8 :: Int),
              "service_tier" .= ("priority" :: Text),
              "speed" .= ("fast" :: Text),
              "output_tokens_details" .= object ["thinking_tokens" .= (5 :: Int)]
            ]
        )
        (messageFixture [])

unaryEvidence :: IO ()
unaryEvidence = do
  request <- sampleRequest baseConversation
  let app req send =
        let result = case lookup "x-case" (Wai.requestHeaders req) of
              Just "malformed" -> addField "stop_details" (tagged "refusal" ["explanation" .= True]) messageWithEvidence
              _ -> messageWithEvidence
         in send (json status200 [] result)
  withClient app $ \client -> do
    Response _ result <- createMessage client defaultRequestOptions request >>= expectRight
    assertEqual "unary stop details" (Just (RefusalDetails (Just "other") (Just "declined") Nothing)) (result ^. #stopDetails)
    assertEqual "unary reasoning" (Just (OutputTokenDetails (Just 5))) (result ^. #usage . #usageEvidence . #outputTokensDetails)
    assertEqual "provider JSON" messageWithEvidence (toJSON result)
    createMessage client defaultRequestOptions {extraHeaders = [("x-case", "malformed")]} request >>= \case
      Left (DecodeError _ _) -> pure ()
      _ -> fail "expected malformed stop details to fail decoding"

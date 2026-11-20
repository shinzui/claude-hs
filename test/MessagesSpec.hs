module MessagesSpec (run, baseConversation, messageFixture, sampleRequest) where

import Claude.Client
import Claude.Messages
import Data.Aeson (Value, object, (.=))
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Network.HTTP.Types (status200, status302, status429, status502)
import Network.Wai qualified as Wai
import Support.Server

baseConversation :: Conversation
baseConversation = Conversation "candidate-model" (Message User (InputText "Hello" :| []) :| []) Nothing

sampleRequest :: Conversation -> IO MessageRequest
sampleRequest convo = maybe (fail "internal fixture limit") (pure . MessageRequest convo) (maxTokens 256)

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
    assertEqual "typed message" (MessageResponse "msg_1" "candidate-model" Assistant [OutputText "Hi", UnknownBlock "future" future] (Just EndTurn) Nothing (Usage 17 8)) response
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
      convo = Conversation "candidate-model" history (Just "Use the image.")
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
    turn role blocks = object ["role" .= (role :: Text), "content" .= (blocks :: [Value])]

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
      Left err@(ApiStatusError meta (Just (ApiError "rate_limit_error" detail))) -> do
        assert "retry metadata" (meta == ResponseMetadata (Just "req_rate") (Just "3") 429)
        assertEqual "redacted detail" "Echo [redacted]" detail
        assert "secret absent from Show" (not ("loopback-secret" `isInfixOf` show err))
      _ -> fail "Expected structured rate limit"
    call "gateway" >>= \case
      Left (ApiStatusError (ResponseMetadata Nothing Nothing 502) Nothing) -> pure ()
      _ -> fail "Expected non-JSON status error"
    call "invalid-json" >>= \case
      Left (DecodeError (ResponseMetadata (Just "req_decode") Nothing 200) _) -> pure ()
      _ -> fail "Expected JSON decode failure"
    call "redirect" >>= \case
      Left (ApiStatusError (ResponseMetadata _ _ 302) Nothing) -> pure ()
      _ -> fail "Expected redirect to be returned as HTTP failure"
    call "disconnect" >>= \case
      Left (TransportError _ Disconnected) -> pure ()
      Left err -> fail ("Expected disconnected request, got " <> show err)
      Right _ -> fail "Disconnected request succeeded"
  readIORef calls >>= assertEqual "one dispatch per operation" 5

module StreamingSpec (run) where

import Claude.Client
import Claude.Messages
import Claude.Streaming
import Control.Concurrent (forkFinally, killThread, newEmptyMVar, putMVar, takeMVar, threadDelay)
import Control.Exception (bracket, try)
import Control.Lens ((&), (.~), (^.))
import Control.Monad (forM_, void)
import Data.Aeson (Key, Value (..), eitherDecode, eitherDecodeStrict, encode, object, toJSON, (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder (byteString)
import Data.ByteString.Char8 qualified as BSC
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import FeaturesSpec (thinkingBlock, webCitation)
import MessagesSpec (baseConversation, messageFixture, sampleRequest)
import Network.HTTP.Types (status200)
import Network.Wai qualified as Wai
import Numeric (showHex)
import Support.Server

run :: IO ()
run = do
  gatedRelease
  fragmentedEvents
  streamToolContinuation
  streamFailures
  putStrLn "Streaming: delivery, cancellation, framing, continuation and failure fixtures passed"

event :: Text -> [(Key, Value)] -> Value
event tag fields = object (("type" .= tag) : fields)

frame :: Value -> ByteString
frame payload = "data: " <> LBS.toStrict (encode payload) <> "\n\n"

messageStart :: Value
messageStart = event "message_start" ["message" .= messageFixture []]

textDelta :: Int -> Text -> Value
textDelta index value = event "content_block_delta" ["index" .= index, "delta" .= event "text_delta" ["text" .= value]]

blockStart :: Int -> Value -> Value
blockStart index value = event "content_block_start" ["index" .= index, "content_block" .= value]

blockDelta :: Int -> Value -> Value
blockDelta index value = event "content_block_delta" ["index" .= index, "delta" .= value]

blockStop :: Int -> Value
blockStop index = event "content_block_stop" ["index" .= index]

messageStop :: Value
messageStop = event "message_stop" []

sse :: ByteString -> Wai.Response
sse body = Wai.responseLBS status200 [("content-type", "text/event-stream"), ("request-id", "req_stream")] (LBS.fromStrict body)

gatedRelease :: IO ()
gatedRelease = forM_ (["stop", "exception", "cancel", "finish"] :: [String]) $ \mode -> do
  entered <- newEmptyMVar
  released <- newEmptyMVar
  allowFinish <- newEmptyMVar
  never <- newEmptyMVar
  request <- sampleRequest baseConversation
  let app req send = do
        sent <- requestJson req
        assertEqual "stream request" (addStreamFlag (toJSON request)) sent
        assertEqual "stream accept" (Just "text/event-stream") (lookup "accept" (Wai.requestHeaders req))
        send $
          Wai.responseRaw
            ( \recv write -> do
                write "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\nRequest-Id: req_gated\r\n\r\n"
                write (httpChunk (frame messageStart))
                if mode == "finish" then takeMVar allowFinish >> write (httpChunk (frame messageStop)) else pure ()
                recv >>= putMVar released
            )
            (sse "")
      checkStart meta streamEvent = do
        assertEqual "stream correlation" (Just "req_gated") (meta ^. #requestId)
        case streamEvent ^. #eventPayload of
          MessageStart _ -> putMVar entered ()
          MessageStop -> pure ()
          _ -> fail "Unexpected event"
  withClient app $ \client -> do
    let streaming = streamMessage client defaultRequestOptions request
    case mode of
      "stop" -> do
        Response _ terminal <- streaming (\meta ev -> checkStart meta ev >> pure Stop) >>= expectRight
        assertEqual "caller stopped" Stopped terminal
        takeMVar entered
      "exception" -> do
        result <- try (streaming (\meta ev -> checkStart meta ev >> ioError (userError "callback failure")))
        case result of
          Left (_ :: IOError) -> takeMVar entered
          Right _ -> fail "Callback exception did not propagate"
      "cancel" -> do
        finished <- newEmptyMVar
        bracket
          (forkFinally (void (streaming (\meta ev -> checkStart meta ev >> takeMVar never))) (putMVar finished))
          killThread
          ( \tid -> do
              takeMVar entered
              killThread tid
              takeMVar finished >>= \case
                Left _ -> pure ()
                Right () -> fail "Expected cancellation"
          )
      _ -> do
        Response _ terminal <-
          streaming
            ( \meta ev -> do
                checkStart meta ev
                case ev ^. #eventPayload of
                  MessageStart _ -> putMVar allowFinish ()
                  _ -> pure ()
                pure Continue
            )
            >>= expectRight
        assertEqual "provider finished" Finished terminal
    takeMVar released >>= assertEqual ("socket released after " <> mode) BS.empty
  where
    httpChunk bytes = BSC.pack (showHex (BS.length bytes) "") <> "\r\n" <> bytes <> "\r\n"
    addStreamFlag (Object fields) = Object (KeyMap.insert "stream" (Bool True) fields)
    addStreamFlag raw = raw

fragmentedEvents :: IO ()
fragmentedEvents = do
  request <- sampleRequest baseConversation
  let futureDelta = event "future_delta" ["unknown" .= True]
      transcript =
        ": comment\r\nevent: message_start\r\ndata: "
          <> LBS.toStrict (encode messageStart)
          <> "\r\n\r\nevent: ping\ndata: {\ndata: \"type\": \"ping\"}\n\n"
          <> BS.concat
            ( map
                frame
                [ blockStart 0 (event "text" ["text" .= ("" :: Text)]),
                  textDelta 0 "café",
                  blockDelta 0 (event "citations_delta" ["citation" .= webCitation]),
                  blockStop 0,
                  blockStart 1 (thinkingBlock "" ""),
                  blockDelta 1 (event "thinking_delta" ["thinking" .= ("summary" :: Text)]),
                  blockDelta 1 (event "signature_delta" ["signature" .= ("opaque-signature" :: Text)]),
                  blockDelta 1 futureDelta,
                  blockStop 1,
                  event "future_event" ["v" .= True],
                  event
                    "message_delta"
                    [ "delta" .= object ["stop_reason" .= ("end_turn" :: Text), "stop_sequence" .= Null],
                      "usage" .= object ["input_tokens" .= (20 :: Int), "output_tokens" .= (9 :: Int), "cache_read_input_tokens" .= (5 :: Int)]
                    ],
                  messageStop
                ]
            )
      check split = do
        seen <- newIORef []
        let app req send = do
              _ <- Wai.strictRequestBody req
              if split
                then send $ Wai.responseStream status200 [] $ \write flush ->
                  BS.foldr (\byte next -> write (byteString (BS.singleton byte)) >> flush >> threadDelay 100 >> next) (pure ()) transcript
                else send (sse transcript)
        withClient app $ \client -> do
          Response _ terminal <-
            streamMessage
              client
              defaultRequestOptions
              request
              (\_ item -> modifyIORef' seen (item :) >> pure Continue)
              >>= expectRight
          assertEqual "finished fragmented stream" Finished terminal
          reverse <$> readIORef seen
  whole <- check False
  split <- check True
  assertEqual "single byte fragments" whole split
  case map (^. #eventPayload) split of
    [ MessageStart _,
      Ping,
      ContentBlockStart 0 _,
      ContentBlockDelta 0 (TextDelta "café"),
      ContentBlockDelta 0 (CitationDelta (Citation (WebLocation _ _ _ "encrypted-index") _)),
      ContentBlockStop 0,
      ContentBlockStart 1 _,
      ContentBlockDelta 1 (ThinkingDelta "summary"),
      ContentBlockDelta 1 (SignatureDelta "opaque-signature"),
      ContentBlockDelta 1 (UnknownDelta "future_delta" _),
      ContentBlockStop 1,
      UnknownEvent "future_event",
      MessageDelta (MessageUpdate (Just EndTurn) Nothing) (UsageUpdate (Just 20) (Just 9) Nothing (Just 5) Nothing),
      MessageStop
      ] -> pure ()
    _ -> fail "unexpected event or delta sequence"

streamToolContinuation :: IO ()
streamToolContinuation = do
  request <- sampleRequest baseConversation
  let unsigned = thinkingBlock "" ""
      signed = thinkingBlock "" "signature-stream"
      toolId = "tool_stream" :: Text
      tool input = event "tool_use" ["id" .= toolId, "name" .= ("lookup" :: Text), "input" .= input]
      finalInput = object ["value" .= ("green" :: Text)]
      transcript =
        BS.concat
          ( map
              frame
              [ messageStart,
                blockStart 0 unsigned,
                blockDelta 0 (event "signature_delta" ["signature" .= ("signature-stream" :: Text)]),
                blockStop 0,
                blockStart 1 (tool (object [])),
                blockDelta 1 (event "input_json_delta" ["partial_json" .= ("{\"value\":" :: Text)]),
                blockDelta 1 (event "input_json_delta" ["partial_json" .= ("\"green\"}" :: Text)]),
                blockStop 1,
                messageStop
              ]
          )
      app req send = do
        body <- requestJson req
        if lookup "accept" (Wai.requestHeaders req) == Just "text/event-stream"
          then send (sse transcript)
          else do
            let expectedMessages =
                  toJSON
                    [ toJSON (NonEmpty.head (baseConversation ^. #messages)),
                      object ["role" .= ("assistant" :: Text), "content" .= [signed, tool finalInput]],
                      object ["role" .= ("user" :: Text), "content" .= [event "tool_result" ["tool_use_id" .= toolId, "content" .= ("done" :: Text)]]]
                    ]
            assertEqual
              "HTTP replay of signed stream tool turn"
              (Just expectedMessages)
              ( case body of
                  Object fields -> KeyMap.lookup "messages" fields
                  _ -> Nothing
              )
            send (json status200 [] (messageFixture []))
  withClient app $ \client -> do
    seen <- newIORef []
    _ <-
      streamMessage
        client
        defaultRequestOptions
        request
        (\_ ev -> modifyIORef' seen ((ev ^. #eventPayload) :) >> pure Continue)
        >>= expectRight
    events <- reverse <$> readIORef seen
    case events of
      [ MessageStart starting,
        ContentBlockStart 0 first,
        ContentBlockDelta 0 (SignatureDelta signature),
        ContentBlockStop 0,
        ContentBlockStart 1 second,
        ContentBlockDelta 1 (InputJsonDelta prefix),
        ContentBlockDelta 1 (InputJsonDelta suffix),
        ContentBlockStop 1,
        MessageStop
        ] -> do
          input <- expectRight (eitherDecodeStrict (encodeUtf8 (prefix <> suffix)))
          thinking <- parseBlock "signature" (String signature) first
          called <- parseBlock "input" input second
          let updated = starting & #content .~ [thinking, called]
          reply <- maybe (fail "missing stream continuation") pure (assistantContinuation updated)
          let toolResult = Message User (InputToolResult (ToolResult toolId (ToolResultText "done") Nothing Nothing) :| [])
              continued = request {conversation = baseConversation {messages = (baseConversation ^. #messages) <> (reply :| [toolResult])}}
          void (createMessage client defaultRequestOptions continued >>= expectRight)
      _ -> fail "Unexpected continuation transcript"
  where
    parseBlock :: Key -> Value -> OutputBlock -> IO OutputBlock
    parseBlock key item block = case blockJSON block of
      Object fields -> expectRight (eitherDecode (encode (Object (KeyMap.insert key item fields))))
      _ -> fail "Expected a block object"

streamFailures :: IO ()
streamFailures = do
  request <- sampleRequest baseConversation
  let malformed = event "content_block_delta" ["index" .= (0 :: Int), "delta" .= event "signature_delta" []]
      apiError = event "error" ["error" .= object ["type" .= ("overloaded_error" :: Text), "message" .= ("Retry later loopback-secret" :: Text)]]
      exercise payload verify = withClient (\_ send -> send (sse (frame messageStart <> payload))) $ \client ->
        streamMessage client defaultRequestOptions request (\_ _ -> pure Continue) >>= verify
      decodeFailure = \case
        Left (DecodeError meta _) -> assertEqual "decode failure correlation" (Just "req_stream") (meta ^. #requestId)
        _ -> fail "Expected stream decode failure"
  exercise "" decodeFailure
  exercise (frame malformed) decodeFailure
  exercise (frame apiError) $ \case
    Left (StreamApiError meta (ApiError "overloaded_error" detail)) -> do
      assertEqual "stream error correlation" (Just "req_stream") (meta ^. #requestId)
      assertEqual "stream error redaction" "Retry later [redacted]" detail
    _ -> fail "Expected a typed in-stream API error"
  withClient (\_ _ -> fail "Incompatible request dispatched") $ \client -> do
    let legacy = case toJSON request of
          Object fields -> Object (KeyMap.insert "temperature" (toJSON (0.5 :: Double)) fields)
          raw -> raw
    streamMessageValue client defaultRequestOptions legacy (\_ _ -> pure Continue) >>= \case
      Left (InvalidRequest _) -> pure ()
      _ -> fail "Expected local failure for removed sampling"

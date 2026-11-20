-- | Deliver Messages events as they arrive on a scoped HTTP connection.
module Claude.Streaming
  ( streamMessage,
    streamMessageValue,
    decodeStreamEvent,
    consumeEventStream,
    StreamControl (..),
    StreamEnd (..),
    StreamEvent (..),
    StreamPayload (..),
    BlockDelta (..),
    MessageUpdate (..),
    UsageUpdate (..),
    applyUsageUpdate,
  )
where

import Claude.Client
import Claude.Internal.Http (BodyReader, decodeResponse, redactApiError, runRequest)
import Claude.Internal.Request (validateMessages)
import Claude.Internal.Sse (foldEvents)
import Claude.Messages
import Claude.Messages.Usage (mergeUsageEvidence)
import Control.Applicative ((<|>))
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT, runExceptT, throwE)
import Data.Aeson (FromJSON (..), Object, Value (..), toJSON, withObject, (.:), (.:?))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (parseEither)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import GHC.Generics (Generic)
import Numeric.Natural (Natural)

data StreamControl = Continue | Stop
  deriving stock (Eq, Show)

data StreamEnd = Finished | Stopped
  deriving stock (Eq, Show)

data StreamEvent = StreamEvent
  { eventPayload :: !StreamPayload,
    eventJSON :: !Value
  }
  deriving stock (Eq, Show, Generic)

data StreamPayload
  = MessageStart !MessageResponse
  | ContentBlockStart !Natural !OutputBlock
  | ContentBlockDelta !Natural !BlockDelta
  | ContentBlockStop !Natural
  | MessageDelta !MessageUpdate !UsageUpdate
  | MessageStop
  | Ping
  | UnknownEvent !Text
  deriving stock (Eq, Show)

data BlockDelta
  = TextDelta !Text
  | InputJsonDelta !Text
  | CitationDelta !Citation
  | ThinkingDelta !Text
  | SignatureDelta !Text
  | UnknownDelta !Text !Value
  deriving stock (Eq, Show)

data MessageUpdate = MessageUpdate
  { stopReason :: !(Maybe StopReason),
    stopSequence :: !(Maybe Text),
    stopDetails :: !(Maybe StopDetails),
    updatedContainer :: !(Maybe ContainerInfo)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON MessageUpdate where
  parseJSON = withObject "message delta" $ \o -> MessageUpdate <$> o .:? "stop_reason" <*> o .:? "stop_sequence" <*> o .:? "stop_details" <*> o .:? "container"

-- | The provider reports cumulative counters. Missing counters leave
-- earlier observations in effect.
data UsageUpdate = UsageUpdate
  { inputTokens :: !(Maybe Natural),
    outputTokens :: !(Maybe Natural),
    cacheCreationInputTokens :: !(Maybe Natural),
    cacheReadInputTokens :: !(Maybe Natural),
    serverToolUse :: !(Maybe Object),
    cacheCreation :: !(Maybe Object),
    usageEvidence :: !UsageEvidence
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON UsageUpdate where
  parseJSON = withObject "stream usage" $ \o ->
    UsageUpdate
      <$> o .:? "input_tokens"
      <*> o .:? "output_tokens"
      <*> o .:? "cache_creation_input_tokens"
      <*> o .:? "cache_read_input_tokens"
      <*> o .:? "server_tool_use"
      <*> o .:? "cache_creation"
      <*> parseJSON (Object o)

-- | Apply a cumulative update while retaining each unreported counter.
applyUsageUpdate :: Usage -> UsageUpdate -> Usage
applyUsageUpdate previous update = case (previous, update) of
  (Usage input output written read_ cache tools evidence, UsageUpdate input' output' written' read' tools' cache' evidence') ->
    Usage
      (fromMaybe input input')
      (fromMaybe output output')
      (written' <|> written)
      (read' <|> read_)
      (mergeObjects cache cache')
      (mergeObjects tools tools')
      (mergeUsageEvidence evidence evidence')
  where
    mergeObjects (Just old) (Just new) = Just (KeyMap.union new old)
    mergeObjects old new = new <|> old

instance FromJSON BlockDelta where
  parseJSON raw =
    withObject
      "content block delta"
      ( \o ->
          o .: "type" >>= \case
            "text_delta" -> TextDelta <$> o .: "text"
            "input_json_delta" -> InputJsonDelta <$> o .: "partial_json"
            "citations_delta" -> CitationDelta <$> o .: "citation"
            "thinking_delta" -> ThinkingDelta <$> o .: "thinking"
            "signature_delta" -> SignatureDelta <$> o .: "signature"
            tag -> pure (UnknownDelta tag raw)
      )
      raw

data FrameEvent = FrameEvent !Text !(Either ApiError StreamPayload) !Value

instance FromJSON FrameEvent where
  parseJSON raw = withObject "stream event" decode raw
    where
      decode o = do
        tag <- o .: "type"
        observed <- case tag of
          "error" -> Left <$> o .: "error"
          _ ->
            Right <$> case tag of
              "message_start" -> MessageStart <$> o .: "message"
              "content_block_start" -> ContentBlockStart <$> o .: "index" <*> o .: "content_block"
              "content_block_delta" -> ContentBlockDelta <$> o .: "index" <*> o .: "delta"
              "content_block_stop" -> ContentBlockStop <$> o .: "index"
              "message_delta" -> MessageDelta <$> o .: "delta" <*> o .: "usage"
              "message_stop" -> pure MessageStop
              "ping" -> pure Ping
              other -> pure (UnknownEvent other)
        pure (FrameEvent tag observed raw)

-- | Decode a recorded JSON event with the same codec used by 'streamMessage'.
-- The inner error is a provider error event. The outer error describes an
-- invalid event object.
decodeStreamEvent :: Value -> Either String (Either ApiError StreamEvent)
decodeStreamEvent raw = do
  FrameEvent _ payload original <- parseEither parseJSON raw
  pure (fmap (\event -> StreamEvent event original) payload)

-- | The callback runs synchronously. 'Stop' releases the response without
-- waiting for EOF. An observed @message_stop@ ends the operation as 'Finished'.
-- Callback exceptions and cancellation propagate after cleanup.
streamMessage ::
  Client ->
  RequestOptions ->
  MessageRequest ->
  (ResponseMetadata -> StreamEvent -> IO StreamControl) ->
  IO (Either ClientError (Response StreamEnd))
streamMessage client options request =
  streamMessageValue client options (toJSON request)

-- | Bridge an existing versioned Messages encoder. Require the common request
-- envelope and preserve its fields, taking ownership of the stream flag.
streamMessageValue ::
  Client ->
  RequestOptions ->
  Value ->
  (ResponseMetadata -> StreamEvent -> IO StreamControl) ->
  IO (Either ClientError (Response StreamEnd))
streamMessageValue client options body consume =
  case validateMessages client True body of
    Left err -> pure (Left err)
    Right fields ->
      runRequest client "POST" "/v1/messages" [] options "text/event-stream" (Just (Object (KeyMap.insert "stream" (Bool True) fields))) $ \meta readBody ->
        consumeSse meta (redactApiError client) readBody (consume meta)

-- | Consume an already acquired SSE body with the live stream decoder.
-- The caller owns the reader and its lifetime. Errors carry the supplied
-- metadata, and caller exceptions propagate.
consumeEventStream ::
  ResponseMetadata ->
  IO ByteString ->
  (StreamEvent -> IO StreamControl) ->
  IO (Either ClientError StreamEnd)
consumeEventStream meta readBody consume =
  runExceptT (consumeSse meta (\err -> err) (liftIO readBody) consume)

consumeSse ::
  ResponseMetadata ->
  (ApiError -> ApiError) ->
  BodyReader ->
  (StreamEvent -> IO StreamControl) ->
  ExceptT ClientError IO StreamEnd
consumeSse meta protect readBody consume = do
  final <- foldEvents readBody $ \eventName payload -> do
    FrameEvent tag decoded raw <- either throwE pure (decodeResponse meta (LBS.fromStrict payload))
    if maybe False (\name -> name /= "" && name /= encodeUtf8 tag) eventName
      then throwE (DecodeError meta "SSE event name differs from the JSON type")
      else case decoded of
        Left err -> throwE (StreamApiError meta (protect err))
        Right event -> do
          decision <- liftIO (consume (StreamEvent event raw))
          pure $ case (event, decision) of
            (MessageStop, _) -> Just Finished
            (_, Stop) -> Just Stopped
            _ -> Nothing
  maybe (throwE (DecodeError meta "Stream ended before message_stop")) pure final

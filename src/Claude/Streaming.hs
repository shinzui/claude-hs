-- | Deliver Messages events as they arrive on a scoped HTTP connection.
module Claude.Streaming
  ( streamMessage,
    streamMessageValue,
    StreamControl (..),
    StreamEnd (..),
    StreamEvent (..),
    StreamPayload (..),
    BlockDelta (..),
    MessageUpdate (..),
    UsageUpdate (..),
  )
where

import Claude.Client
import Claude.Internal.Http (decodeResponse, redactApiError, runRequest)
import Claude.Internal.Request (validateMessages)
import Claude.Internal.Sse (foldEvents)
import Claude.Messages
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (throwE)
import Data.Aeson (FromJSON (..), Object, Value (..), toJSON, withObject, (.:), (.:?))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as LBS
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
    stopSequence :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON MessageUpdate where
  parseJSON = withObject "message delta" $ \o -> MessageUpdate <$> o .:? "stop_reason" <*> o .:? "stop_sequence"

-- | The provider reports cumulative counters. Missing counters leave
-- earlier observations in effect.
data UsageUpdate = UsageUpdate
  { inputTokens :: !(Maybe Natural),
    outputTokens :: !(Maybe Natural),
    cacheCreationInputTokens :: !(Maybe Natural),
    cacheReadInputTokens :: !(Maybe Natural),
    serverToolUse :: !(Maybe Object)
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
      runRequest client "POST" "/v1/messages" [] options "text/event-stream" (Just (Object (KeyMap.insert "stream" (Bool True) fields))) $ \meta readBody -> do
        final <- foldEvents readBody $ \eventName payload -> do
          FrameEvent tag decoded raw <- either throwE pure (decodeResponse meta (LBS.fromStrict payload))
          if maybe False (\name -> name /= "" && name /= encodeUtf8 tag) eventName
            then throwE (DecodeError meta "SSE event name differs from the JSON type")
            else case decoded of
              Left err -> throwE (StreamApiError meta (redactApiError client err))
              Right event -> do
                decision <- liftIO (consume meta (StreamEvent event raw))
                pure $ case (event, decision) of
                  (MessageStop, _) -> Just Finished
                  (_, Stop) -> Just Stopped
                  _ -> Nothing
        maybe (throwE (DecodeError meta "Stream ended before message_stop")) pure final

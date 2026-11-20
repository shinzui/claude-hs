-- | Synchronous Messages and input token counting.
module Claude.Messages
  ( MessageRequest (..),
    CountRequest (..),
    Conversation (..),
    Message (..),
    Role (..),
    InputBlock (..),
    ImageSource (..),
    module Claude.Messages.Features,
    assistantContinuation,
    responseText,
    MessageResponse (..),
    StopReason (..),
    Usage (..),
    TokenCount (..),
    MaxTokens,
    maxTokens,
    createMessage,
    countTokens,
  )
where

import Claude.Client (Client, ClientError, RequestOptions, Response)
import Claude.Internal.Http (jsonRequest)
import Claude.Messages.Features
import Control.Lens ((^.))
import Data.Aeson (FromJSON (..), Object, ToJSON (..), object, withObject, withText, (.:), (.:?), (.=))
import Data.Aeson.Types (Pair)
import Data.Generics.Labels ()
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import GHC.Generics (Generic)
import Numeric.Natural (Natural)

data Role = User | Assistant
  deriving stock (Eq, Show)

instance ToJSON Role where
  toJSON User = "user"
  toJSON Assistant = "assistant"

instance FromJSON Role where
  parseJSON = withText "role" $ \case
    "user" -> pure User
    "assistant" -> pure Assistant
    _ -> fail "expected user or assistant"

data ImageSource = Base64Image !Text !Text | ImageUrl !Text
  deriving stock (Eq, Show)

instance ToJSON ImageSource where
  toJSON (Base64Image media bytes) = object ["type" .= ("base64" :: Text), "media_type" .= media, "data" .= bytes]
  toJSON (ImageUrl url) = object ["type" .= ("url" :: Text), "url" .= url]

data InputBlock
  = InputText !Text
  | InputImage !ImageSource
  | InputDocument !Document
  | InputToolResult !ToolResult
  | CachedText !Text !CacheControl
  | CachedImage !ImageSource !CacheControl
  | ReplayBlock !OutputBlock
  | VersionedBlock !Object
  deriving stock (Eq, Show)

instance ToJSON InputBlock where
  toJSON = \case
    InputText body -> object ["type" .= ("text" :: Text), "text" .= body]
    InputImage source -> object ["type" .= ("image" :: Text), "source" .= source]
    InputDocument doc -> toJSON doc
    InputToolResult result -> toJSON result
    CachedText body cache -> object ["type" .= ("text" :: Text), "text" .= body, "cache_control" .= cache]
    CachedImage source cache -> object ["type" .= ("image" :: Text), "source" .= source, "cache_control" .= cache]
    ReplayBlock block -> blockJSON block
    VersionedBlock block -> toJSON block

data Message = Message
  { role :: !Role,
    content :: !(NonEmpty InputBlock)
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON Message where
  toJSON msg = object ["role" .= (msg ^. #role), "content" .= (msg ^. #content)]

data Conversation = Conversation
  { model :: !Text,
    messages :: !(NonEmpty Message),
    system :: !(Maybe SystemPrompt),
    features :: !MessageFeatures
  }
  deriving stock (Eq, Show, Generic)

newtype MaxTokens = MaxTokens Natural
  deriving stock (Eq, Show)
  deriving newtype (ToJSON)

maxTokens :: Natural -> Maybe MaxTokens
maxTokens 0 = Nothing
maxTokens n = Just (MaxTokens n)

data MessageRequest = MessageRequest
  { conversation :: !Conversation,
    outputLimit :: !MaxTokens,
    stopSequences :: ![Text]
  }
  deriving stock (Eq, Show, Generic)

newtype CountRequest = CountRequest Conversation
  deriving stock (Eq, Show)

conversationFields :: Conversation -> [Pair]
conversationFields convo =
  ["model" .= (convo ^. #model), "messages" .= (convo ^. #messages)]
    <> optional "system" (convo ^. #system)
    <> optional "output_config" (opts ^. #outputConfig)
    <> optional "thinking" (opts ^. #thinking)
    <> optional "cache_control" (opts ^. #cacheControl)
    <> ["tools" .= offered | let offered = opts ^. #tools, not (null offered)]
    <> optional "tool_choice" (opts ^. #toolChoice)
    <> optional "speed" (opts ^. #speed)
  where
    opts = convo ^. #features
    optional key = maybe [] (\item -> [key .= item])

instance ToJSON MessageRequest where
  toJSON request =
    object $
      ["max_tokens" .= (request ^. #outputLimit)]
        <> conversationFields (request ^. #conversation)
        <> ["stop_sequences" .= stops | let stops = request ^. #stopSequences, not (null stops)]

instance ToJSON CountRequest where
  toJSON (CountRequest convo) = object (conversationFields convo)

data StopReason = EndTurn | MaxTokensReached | StopSequence | ToolUse | PauseTurn | Refusal | UnknownStopReason !Text
  deriving stock (Eq, Show)

instance FromJSON StopReason where
  parseJSON =
    withText "stop_reason" $
      pure . \case
        "end_turn" -> EndTurn
        "max_tokens" -> MaxTokensReached
        "stop_sequence" -> StopSequence
        "tool_use" -> ToolUse
        "pause_turn" -> PauseTurn
        "refusal" -> Refusal
        other -> UnknownStopReason other

data Usage = Usage
  { inputTokens :: !Natural,
    outputTokens :: !Natural,
    cacheCreationInputTokens :: !(Maybe Natural),
    cacheReadInputTokens :: !(Maybe Natural),
    cacheCreation :: !(Maybe Object),
    serverToolUse :: !(Maybe Object)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON Usage where
  parseJSON = withObject "usage" $ \o ->
    Usage
      <$> o .: "input_tokens"
      <*> o .: "output_tokens"
      <*> o .:? "cache_creation_input_tokens"
      <*> o .:? "cache_read_input_tokens"
      <*> o .:? "cache_creation"
      <*> o .:? "server_tool_use"

data MessageResponse = MessageResponse
  { id :: !Text,
    model :: !Text,
    role :: !Role,
    content :: ![OutputBlock],
    stopReason :: !(Maybe StopReason),
    stopSequence :: !(Maybe Text),
    usage :: !Usage
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON MessageResponse where
  parseJSON = withObject "message" $ \o ->
    MessageResponse
      <$> o .: "id"
      <*> o .: "model"
      <*> o .: "role"
      <*> o .: "content"
      <*> o .:? "stop_reason"
      <*> o .:? "stop_sequence"
      <*> o .: "usage"

-- | Replay this history only against its originating provider and model.
assistantContinuation :: MessageResponse -> Maybe Message
assistantContinuation response = do
  if response ^. #role == Assistant then pure () else Nothing
  blocks <- NonEmpty.nonEmpty (response ^. #content)
  pure (Message Assistant (fmap ReplayBlock blocks))

responseText :: MessageResponse -> Text
responseText response =
  Text.concat [body | block <- response ^. #content, OutputText body _ <- [blockContent block]]

newtype TokenCount = TokenCount {inputTokens :: Natural}
  deriving stock (Eq, Show, Generic)

instance FromJSON TokenCount where
  parseJSON = withObject "token count" $ \o -> TokenCount <$> o .: "input_tokens"

createMessage :: Client -> RequestOptions -> MessageRequest -> IO (Either ClientError (Response MessageResponse))
createMessage client options = jsonRequest client "POST" "/v1/messages" [] options . Just . toJSON

countTokens :: Client -> RequestOptions -> CountRequest -> IO (Either ClientError (Response TokenCount))
countTokens client options = jsonRequest client "POST" "/v1/messages/count_tokens" [] options . Just . toJSON

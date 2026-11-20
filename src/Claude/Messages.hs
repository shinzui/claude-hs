-- | Synchronous Messages and input token counting.
module Claude.Messages
  ( MessageRequest (..),
    CountRequest (..),
    Conversation (..),
    Message (..),
    Role (..),
    InputBlock (..),
    ImageSource (..),
    OutputBlock (..),
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
import Control.Lens ((^.))
import Data.Aeson (FromJSON (..), ToJSON (..), Value, object, withObject, withText, (.:), (.:?), (.=))
import Data.Aeson.Types (Pair)
import Data.Generics.Labels ()
import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
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

data InputBlock = InputText !Text | InputImage !ImageSource
  deriving stock (Eq, Show)

instance ToJSON InputBlock where
  toJSON = \case
    InputText body -> object ["type" .= ("text" :: Text), "text" .= body]
    InputImage source -> object ["type" .= ("image" :: Text), "source" .= source]

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
    system :: !(Maybe Text)
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
    outputLimit :: !MaxTokens
  }
  deriving stock (Eq, Show, Generic)

newtype CountRequest = CountRequest Conversation
  deriving stock (Eq, Show)

conversationFields :: Conversation -> [Pair]
conversationFields convo =
  ["model" .= (convo ^. #model), "messages" .= (convo ^. #messages)]
    <> ["system" .= prompt | Just prompt <- [convo ^. #system]]

instance ToJSON MessageRequest where
  toJSON request = object (("max_tokens" .= (request ^. #outputLimit)) : conversationFields (request ^. #conversation))

instance ToJSON CountRequest where
  toJSON (CountRequest convo) = object (conversationFields convo)

data OutputBlock = OutputText !Text | UnknownBlock !Text !Value
  deriving stock (Eq, Show)

instance FromJSON OutputBlock where
  parseJSON raw =
    withObject
      "content block"
      ( \o ->
          o .: "type" >>= \case
            "text" -> OutputText <$> o .: "text"
            tag -> pure (UnknownBlock tag raw)
      )
      raw

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
    outputTokens :: !Natural
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON Usage where
  parseJSON = withObject "usage" $ \o -> Usage <$> o .: "input_tokens" <*> o .: "output_tokens"

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

newtype TokenCount = TokenCount {inputTokens :: Natural}
  deriving stock (Eq, Show, Generic)

instance FromJSON TokenCount where
  parseJSON = withObject "token count" $ \o -> TokenCount <$> o .: "input_tokens"

createMessage :: Client -> RequestOptions -> MessageRequest -> IO (Either ClientError (Response MessageResponse))
createMessage client options = jsonRequest client "POST" "/v1/messages" [] options . Just . toJSON

countTokens :: Client -> RequestOptions -> CountRequest -> IO (Either ClientError (Response TokenCount))
countTokens client options = jsonRequest client "POST" "/v1/messages/count_tokens" [] options . Just . toJSON

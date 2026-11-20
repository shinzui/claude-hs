-- | Synchronous Messages and input token counting.
module Claude.Messages
  ( MessageRequest (..),
    withRequestControls,
    messageRequestControls,
    CountRequest (..),
    Conversation (..),
    conversationHistory,
    withConversationHistory,
    Message (..),
    Role (..),
    InputBlock (..),
    ImageSource (..),
    module Claude.Messages.Features,
    assistantContinuation,
    continueMessage,
    responseText,
    MessageResponse (..),
    ContainerInfo (..),
    StopDetails (..),
    UsageEvidence (..),
    OutputTokenDetails (..),
    ServerToolCounts (..),
    UsageIteration (..),
    StopReason (..),
    Usage (..),
    TokenCount (..),
    MaxTokens,
    maxTokens,
    maxTokensValue,
    cacheOnly,
    createMessage,
    countTokens,
  )
where

import Claude.Client (Client, ClientError, RequestOptions, Response)
import Claude.Internal.Http (jsonRequest)
import Claude.Internal.Request (MessagesEndpoint (Count, Create), validateMessages)
import Claude.Messages.Features
import Claude.Messages.Usage (OutputTokenDetails (..), ServerToolCounts (..), UsageEvidence (..), UsageIteration (..))
import Control.Applicative ((<|>))
import Control.Lens ((&), (.~), (^.))
import Data.Aeson (FromJSON (..), Key, Object, ToJSON (..), Value (..), object, withObject, withText, (.!=), (.:), (.:?), (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Pair, Parser)
import Data.Generics.Labels ()
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Numeric.Natural (Natural)

data Role = User | Assistant | System
  deriving stock (Eq, Show)

instance ToJSON Role where
  toJSON User = "user"
  toJSON Assistant = "assistant"
  toJSON System = "system"

instance FromJSON Role where
  parseJSON = withText "role" $ \case
    "user" -> pure User
    "assistant" -> pure Assistant
    "system" -> pure System
    _ -> fail "expected user, assistant or system"

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
  | InputToolUse !Text !Text !Value !(Maybe ToolCaller)
  | ToolAddition !ToolChangeReference !(Maybe CacheControl)
  | ToolRemoval !ToolChangeReference !(Maybe CacheControl)
  | InputFallback !FallbackMarker
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
    InputToolUse ident name_ input caller ->
      object (["type" .= ("tool_use" :: Text), "id" .= ident, "name" .= name_, "input" .= input] <> optional "caller" caller)
    ToolAddition tool cache -> toolChange "tool_addition" tool cache
    ToolRemoval tool cache -> toolChange "tool_removal" tool cache
    InputFallback marker -> toJSON marker
    ReplayBlock block -> blockJSON block
    VersionedBlock block -> toJSON block
    where
      toolChange tag tool cache = object (["type" .= (tag :: Text), "tool" .= tool] <> optional "cache_control" cache)

data Message
  = Message
      { role :: !Role,
        content :: !(NonEmpty InputBlock)
      }
  | CachedMessage
      { role :: !Role,
        content :: !(NonEmpty InputBlock),
        messageCacheControl :: !CacheControl
      }
  deriving stock (Eq, Show, Generic)

instance ToJSON Message where
  toJSON msg =
    object
      ( ["role" .= (msg ^. #role), "content" .= (msg ^. #content)] <> case msg of
          CachedMessage _ _ cache -> ["cache_control" .= cache]
          Message {} -> []
      )

instance FromJSON Message where
  parseJSON = withObject "history message" $ \o -> do
    sender <- o .: "role"
    raw <- o .: "content"
    let blocks = withObject "input block" (pure . VersionedBlock)
    content_ <- (fmap (NonEmpty.singleton . InputText) (parseJSON raw)) <|> (parseJSON raw >>= traverse blocks)
    cache <- o .:? "cache_control"
    pure (maybe (Message sender content_) (CachedMessage sender content_) cache)

data Conversation
  = Conversation
      { model :: !Text,
        messages :: !(NonEmpty Message),
        system :: !(Maybe SystemPrompt),
        features :: !MessageFeatures
      }
  | EmptyConversation
      { model :: !Text,
        system :: !(Maybe SystemPrompt),
        features :: !MessageFeatures
      }
  deriving stock (Eq, Show, Generic)

-- | A total history accessor for both current and legacy conversations.
conversationHistory :: Conversation -> [Message]
conversationHistory (Conversation _ history _ _) = NonEmpty.toList history
conversationHistory (EmptyConversation {}) = []

withConversationHistory :: [Message] -> Conversation -> Conversation
withConversationHistory history convo =
  case NonEmpty.nonEmpty history of
    Just turns -> Conversation (convo ^. #model) turns (convo ^. #system) (convo ^. #features)
    Nothing -> EmptyConversation (convo ^. #model) (convo ^. #system) (convo ^. #features)

newtype MaxTokens = MaxTokens Natural
  deriving stock (Eq, Show)
  deriving newtype (ToJSON)

maxTokens :: Natural -> Maybe MaxTokens
maxTokens 0 = Nothing
maxTokens n = Just (MaxTokens n)

maxTokensValue :: MaxTokens -> Natural
maxTokensValue (MaxTokens value) = value

-- | Populate the prompt cache without generating output in unary Messages.
cacheOnly :: MaxTokens
cacheOnly = MaxTokens 0

data MessageRequest
  = MessageRequest
      { conversation :: !Conversation,
        outputLimit :: !MaxTokens,
        stopSequences :: ![Text]
      }
  | MessageRequestWithControls
      { conversation :: !Conversation,
        outputLimit :: !MaxTokens,
        stopSequences :: ![Text],
        requestControls :: !RequestControls
      }
  deriving stock (Eq, Show, Generic)

withRequestControls :: RequestControls -> MessageRequest -> MessageRequest
withRequestControls controls request =
  MessageRequestWithControls (request ^. #conversation) (request ^. #outputLimit) (request ^. #stopSequences) controls

messageRequestControls :: MessageRequest -> RequestControls
messageRequestControls = \case
  MessageRequestWithControls _ _ _ controls -> controls
  MessageRequest {} -> defaultRequestControls

newtype CountRequest = CountRequest Conversation
  deriving stock (Eq, Show)

conversationFields :: Conversation -> [Pair]
conversationFields convo =
  ["model" .= (convo ^. #model), "messages" .= conversationHistory convo]
    <> optional "system" (convo ^. #system)
    <> optional "output_config" (opts ^. #outputConfig)
    <> optional "thinking" (opts ^. #thinking)
    <> optional "cache_control" (opts ^. #cacheControl)
    <> ["tools" .= offered | let offered = opts ^. #tools, not (null offered)]
    <> optional "tool_choice" (opts ^. #toolChoice)
    <> optional "speed" (opts ^. #speed)
  where
    opts = convo ^. #features

optional :: (ToJSON a) => Key -> Maybe a -> [Pair]
optional key = maybe [] (\item -> [key .= item])

generationFields :: RequestControls -> [Pair]
generationFields controls =
  optional "temperature" (controls ^. #temperature)
    <> optional "top_p" (controls ^. #topP)
    <> optional "top_k" (controls ^. #topK)
    <> optional "metadata" (controls ^. #metadata)
    <> optional "container" (controls ^. #containerId)
    <> optional "context_management" (fmap (\edits -> object ["edits" .= edits]) (controls ^. #contextManagement))
    <> optional "inference_geo" (controls ^. #inferenceGeo)
    <> optional "fallbacks" (controls ^. #fallbacks)

instance ToJSON MessageRequest where
  toJSON request =
    object $
      ["max_tokens" .= (request ^. #outputLimit)]
        <> conversationFields (request ^. #conversation)
        <> generationFields (messageRequestControls request)
        <> ["stop_sequences" .= stops | let stops = request ^. #stopSequences, not (null stops)]

instance ToJSON CountRequest where
  toJSON (CountRequest convo) = object (conversationFields convo)

parseConversation :: Object -> Parser Conversation
parseConversation o = do
  model_ <- o .: "model"
  history <- o .: "messages"
  system_ <- o .:? "system"
  features_ <-
    MessageFeatures
      <$> o .:? "output_config"
      <*> o .:? "thinking"
      <*> o .:? "cache_control"
      <*> (o .:? "tools" .!= [])
      <*> o .:? "tool_choice"
      <*> o .:? "speed"
  pure $ case NonEmpty.nonEmpty history of
    Just turns -> Conversation model_ turns system_ features_
    Nothing -> EmptyConversation model_ system_ features_

instance FromJSON CountRequest where
  parseJSON = withObject "count request" (fmap CountRequest . parseConversation)

instance FromJSON MessageRequest where
  parseJSON = withObject "Messages request" $ \o -> do
    convo <- parseConversation o
    limit <- MaxTokens <$> o .: "max_tokens"
    stops <- o .:? "stop_sequences" .!= []
    context <- o .:? "context_management" >>= traverse (withObject "context management" (.: "edits"))
    controls <-
      RequestControls
        <$> o .:? "temperature"
        <*> o .:? "top_p"
        <*> o .:? "top_k"
        <*> o .:? "metadata"
        <*> o .:? "container"
        <*> pure context
        <*> o .:? "inference_geo"
        <*> o .:? "fallbacks"
    let request = MessageRequest convo limit stops
    pure (if controls == defaultRequestControls then request else withRequestControls controls request)

data StopReason = EndTurn | MaxTokensReached | StopSequence | ToolUse | PauseTurn | Refusal | ModelContextWindowExceeded | UnknownStopReason !Text
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
        "model_context_window_exceeded" -> ModelContextWindowExceeded
        other -> UnknownStopReason other

data Usage = Usage
  { inputTokens :: !Natural,
    outputTokens :: !Natural,
    cacheCreationInputTokens :: !(Maybe Natural),
    cacheReadInputTokens :: !(Maybe Natural),
    cacheCreation :: !(Maybe Object),
    serverToolUse :: !(Maybe Object),
    usageEvidence :: !UsageEvidence
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
      <*> parseJSON (Object o)

data MessageResponse = MessageResponse
  { id :: !Text,
    model :: !Text,
    role :: !Role,
    content :: ![OutputBlock],
    stopReason :: !(Maybe StopReason),
    stopSequence :: !(Maybe Text),
    usage :: !Usage,
    stopDetails :: !(Maybe StopDetails),
    container :: !(Maybe ContainerInfo),
    responseJSON :: !Object
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
      <*> o .:? "stop_details"
      <*> o .:? "container"
      <*> pure o

instance ToJSON MessageResponse where
  toJSON = Object . responseJSON

data StopDetails
  = RefusalDetails
      { category :: !(Maybe Text),
        explanation :: !(Maybe Text),
        recommendedModel :: !(Maybe Text)
      }
  | UnknownStopDetails !Text !Object
  deriving stock (Eq, Show, Generic)

instance FromJSON StopDetails where
  parseJSON = withObject "stop details" $ \o ->
    o .: "type" >>= \case
      "refusal" -> RefusalDetails <$> o .:? "category" <*> o .:? "explanation" <*> o .:? "recommended_model"
      tag -> pure (UnknownStopDetails tag o)

data ContainerInfo = ContainerInfo
  { containerIdentifier :: !Text,
    expiresAt :: !UTCTime
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON ContainerInfo where
  parseJSON = withObject "container" $ \o -> ContainerInfo <$> o .: "id" <*> o .: "expires_at"

-- | Replay this history only against its originating provider and model.
assistantContinuation :: MessageResponse -> Maybe Message
assistantContinuation response = do
  if response ^. #role == Assistant then pure () else Nothing
  blocks <- NonEmpty.nonEmpty (response ^. #content)
  pure (Message Assistant (fmap ReplayBlock blocks))

-- | Append provider history and a user turn to the original request, reusing
-- the returned container. Use only with the original provider and model
-- configuration, including the original tools and fallback settings.
continueMessage :: MessageRequest -> MessageResponse -> NonEmpty InputBlock -> Maybe MessageRequest
continueMessage request response next = do
  let original = request ^. #conversation
      controls = messageRequestControls request
      retained = replayableHistory (response ^. #content)
  assistant <- assistantContinuation (response & #content .~ retained)
  let history = conversationHistory original <> [assistant, Message User next]
      updated = request {conversation = withConversationHistory history original}
  pure $ case response ^. #container of
    Nothing -> updated
    Just info -> withRequestControls (controls {containerId = Just (containerIdentifier info)}) updated

-- Before the last handoff the service accepts text and completed server calls.
-- The marker itself must remain in place relative to both models' output.
replayableHistory :: [OutputBlock] -> [OutputBlock]
replayableHistory blocks =
  case break isFallback (reverse blocks) of
    (_, []) -> filter supported blocks
    (after, marker : before) -> filter beforeFallback (reverse before) <> [marker] <> filter supported (reverse after)
  where
    isFallback block = case blockContent block of
      OutputFallback _ -> True
      _ -> False
    supported block = case blockContent block of
      UnknownBlock _ -> False
      _ -> True
    beforeFallback block = case blockContent block of
      OutputText {} -> True
      OutputFallback _ -> True
      ServerToolUse ident _ _ -> any ((== Just (String ident)) . wireToolId) blocks
      WebSearchToolResult {} -> True
      OutputCodeExecutionResult {} -> True
      OutputToolSearchResult {} -> True
      _ -> False
    wireToolId block = case blockJSON block of
      Object fields -> KeyMap.lookup "tool_use_id" fields
      _ -> Nothing

responseText :: MessageResponse -> Text
responseText response =
  Text.concat [body | block <- response ^. #content, OutputText body _ <- [blockContent block]]

newtype TokenCount = TokenCount {inputTokens :: Natural}
  deriving stock (Eq, Show, Generic)

instance FromJSON TokenCount where
  parseJSON = withObject "token count" $ \o -> TokenCount <$> o .: "input_tokens"

createMessage :: Client -> RequestOptions -> MessageRequest -> IO (Either ClientError (Response MessageResponse))
createMessage client options request =
  case validateMessages client Create (toJSON request) of
    Left err -> pure (Left err)
    Right fields -> jsonRequest client "POST" "/v1/messages" [] options (Just (Object fields))

countTokens :: Client -> RequestOptions -> CountRequest -> IO (Either ClientError (Response TokenCount))
countTokens client options request =
  case validateMessages client Count (toJSON request) of
    Left err -> pure (Left err)
    Right fields -> jsonRequest client "POST" "/v1/messages/count_tokens" [] options (Just (Object fields))

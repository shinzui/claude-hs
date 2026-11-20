-- | Request options and content variants shared by Messages and SSE.
module Claude.Messages.Features
  ( MessageFeatures (..),
    defaultMessageFeatures,
    RequestControls (..),
    defaultRequestControls,
    Compaction (..),
    Fallbacks (..),
    FallbackModel (..),
    OutputConfig (..),
    Effort (..),
    Speed (..),
    Thinking (..),
    ThinkingDisplay (..),
    CacheControl (..),
    CacheTTL (..),
    SystemPrompt (..),
    SystemBlock (..),
    Document (..),
    Tool (..),
    ClientTool (..),
    ToolLoading (..),
    AllowedCaller (..),
    ToolCaller (..),
    ToolSearch (..),
    CodeExecutionVersion (..),
    ToolChangeReference (..),
    WebSearch (..),
    WebSearchVersion (..),
    ToolChoice (..),
    ToolResult (..),
    ToolResultContent (..),
    Citation (..),
    CitationLocation (..),
    WebSearchOutcome (..),
    WebSearchResult (..),
    OutputBlock,
    BlockContent (..),
    ToolSearchOutcome (..),
    CodeExecutionOutcome (..),
    FallbackMarker (..),
    blockContent,
    blockJSON,
  )
where

import Control.Applicative ((<|>))
import Control.Lens ((^.))
import Data.Aeson (FromJSON (..), Key, Object, ToJSON (..), Value (..), object, withArray, withObject, withText, (.!=), (.:), (.:?), (.=))
import Data.Aeson.Types (Pair, Parser)
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.Map.Strict (Map)
import Data.Text (Text)
import GHC.Generics (Generic)
import Numeric.Natural (Natural)

-- | Options accepted by both Messages and count_tokens.
data MessageFeatures = MessageFeatures
  { outputConfig :: !(Maybe OutputConfig),
    thinking :: !(Maybe Thinking),
    cacheControl :: !(Maybe CacheControl),
    tools :: ![Tool],
    toolChoice :: !(Maybe ToolChoice),
    speed :: !(Maybe Speed)
  }
  deriving stock (Eq, Show, Generic)

defaultMessageFeatures :: MessageFeatures
defaultMessageFeatures = MessageFeatures Nothing Nothing Nothing [] Nothing Nothing

-- | Generation controls are excluded from the token-count projection.
data RequestControls = RequestControls
  { temperature :: !(Maybe Double),
    topP :: !(Maybe Double),
    topK :: !(Maybe Natural),
    metadata :: !(Maybe (Map Text Text)),
    containerId :: !(Maybe Text),
    contextManagement :: !(Maybe [Compaction]),
    inferenceGeo :: !(Maybe Text),
    fallbacks :: !(Maybe Fallbacks)
  }
  deriving stock (Eq, Show, Generic)

defaultRequestControls :: RequestControls
defaultRequestControls = RequestControls Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

data Compaction = Compaction
  { instructions :: !(Maybe Text),
    pauseAfterCompaction :: !(Maybe Bool),
    inputTokensTrigger :: !(Maybe Natural)
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON Compaction where
  toJSON (Compaction instructions_ pause trigger) =
    tagged "compact_20260112" $
      optional "instructions" instructions_
        <> optional "pause_after_compaction" pause
        <> ["trigger" .= tagged "input_tokens" ["value" .= tokens] | Just tokens <- [trigger]]

data Fallbacks = DefaultFallbacks | FallbackModels ![FallbackModel]
  deriving stock (Eq, Show)

data FallbackModel = FallbackModel
  { model :: !Text,
    fallbackMaxTokens :: !(Maybe Natural),
    outputConfig :: !(Maybe OutputConfig),
    speed :: !(Maybe Speed),
    thinking :: !(Maybe Thinking)
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON Fallbacks where
  toJSON DefaultFallbacks = "default"
  toJSON (FallbackModels models) = toJSON models

instance ToJSON FallbackModel where
  toJSON (FallbackModel ident limit output speed_ thinking_) =
    object $
      ["model" .= ident]
        <> optional "max_tokens" limit
        <> optional "output_config" output
        <> optional "speed" speed_
        <> optional "thinking" thinking_

data Speed = Standard | Fast | VersionedSpeed !Text
  deriving stock (Eq, Show)

instance ToJSON Speed where
  toJSON Standard = "standard"
  toJSON Fast = "fast"
  toJSON (VersionedSpeed value) = toJSON value

data Effort = Low | Medium | High | ExtraHigh | Maximum | VersionedEffort !Text
  deriving stock (Eq, Show)

instance ToJSON Effort where
  toJSON Low = "low"
  toJSON Medium = "medium"
  toJSON High = "high"
  toJSON ExtraHigh = "xhigh"
  toJSON Maximum = "max"
  toJSON (VersionedEffort value) = toJSON value

data OutputConfig = OutputConfig
  { effort :: !(Maybe Effort),
    schema :: !(Maybe Object)
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON OutputConfig where
  toJSON opts =
    object $
      optional "effort" (opts ^. #effort)
        <> ["format" .= tagged "json_schema" ["schema" .= schema_] | Just schema_ <- [opts ^. #schema]]

data Thinking = Adaptive !(Maybe ThinkingDisplay) | ManualBudget !Natural !(Maybe ThinkingDisplay) | ThinkingDisabled | BetweenTools
  deriving stock (Eq, Show)

data ThinkingDisplay = Summarized | Omitted | Updates
  deriving stock (Eq, Show)

instance ToJSON Thinking where
  toJSON (Adaptive display) = tagged "adaptive" (optional "display" display)
  toJSON (ManualBudget tokens display) = tagged "enabled" (("budget_tokens" .= tokens) : optional "display" display)
  toJSON ThinkingDisabled = tagged "disabled" []
  toJSON BetweenTools = tagged "between_tools" []

instance ToJSON ThinkingDisplay where
  toJSON Summarized = "summarized"
  toJSON Omitted = "omitted"
  toJSON Updates = "updates"

newtype CacheControl = Ephemeral (Maybe CacheTTL)
  deriving stock (Eq, Show)

data CacheTTL = FiveMinutes | OneHour
  deriving stock (Eq, Show)

instance ToJSON CacheControl where
  toJSON (Ephemeral ttl) = tagged "ephemeral" (optional "ttl" ttl)

instance ToJSON CacheTTL where
  toJSON FiveMinutes = "5m"
  toJSON OneHour = "1h"

data SystemPrompt = SystemText !Text | SystemBlocks ![SystemBlock]
  deriving stock (Eq, Show)

data SystemBlock = SystemBlock
  { text :: !Text,
    cacheControl :: !(Maybe CacheControl)
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON SystemPrompt where
  toJSON (SystemText text_) = toJSON text_
  toJSON (SystemBlocks blocks) = toJSON blocks

instance ToJSON SystemBlock where
  toJSON block = tagged "text" (("text" .= (block ^. #text)) : optional "cache_control" (block ^. #cacheControl))

data Document = PlainTextDocument
  { text :: !Text,
    title :: !(Maybe Text),
    context :: !(Maybe Text),
    citationsEnabled :: !Bool,
    cacheControl :: !(Maybe CacheControl)
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON Document where
  toJSON doc =
    tagged "document" $
      [ "source" .= tagged "text" ["media_type" .= ("text/plain" :: Text), "data" .= (doc ^. #text)],
        "citations" .= object ["enabled" .= (doc ^. #citationsEnabled)]
      ]
        <> optional "title" (doc ^. #title)
        <> optional "context" (doc ^. #context)
        <> optional "cache_control" (doc ^. #cacheControl)

data Tool
  = CustomTool !ClientTool
  | ConfiguredTool !ClientTool !ToolLoading
  | WebSearchTool !WebSearch
  | ToolSearchTool !ToolSearch !(Maybe CacheControl)
  | CodeExecutionTool !CodeExecutionVersion !(Maybe CacheControl)
  | VersionedTool !Object
  deriving stock (Eq, Show)

data ClientTool = ClientTool
  { name :: !Text,
    description :: !(Maybe Text),
    inputSchema :: !Object,
    strict :: !(Maybe Bool),
    cacheControl :: !(Maybe CacheControl)
  }
  deriving stock (Eq, Show, Generic)

data ToolLoading = ToolLoading
  { deferLoading :: !(Maybe Bool),
    allowedCallers :: !(Maybe [AllowedCaller])
  }
  deriving stock (Eq, Show, Generic)

data AllowedCaller = AllowDirect | AllowCodeExecution !CodeExecutionVersion | AllowVersionedCaller !Text
  deriving stock (Eq, Show)

data ToolCaller = DirectCaller | CodeExecutionCaller !CodeExecutionVersion !Text | VersionedCaller !Text !Object
  deriving stock (Eq, Show)

data ToolSearch = RegexSearch20251119 | BM25Search20251119
  deriving stock (Eq, Show)

data CodeExecutionVersion = CodeExecution20250825 | CodeExecution20260120
  deriving stock (Eq, Show)

codeExecutionTag :: CodeExecutionVersion -> Text
codeExecutionTag CodeExecution20250825 = "code_execution_20250825"
codeExecutionTag CodeExecution20260120 = "code_execution_20260120"

instance ToJSON AllowedCaller where
  toJSON AllowDirect = "direct"
  toJSON (AllowCodeExecution version_) = toJSON (codeExecutionTag version_)
  toJSON (AllowVersionedCaller name_) = toJSON name_

instance ToJSON ToolCaller where
  toJSON DirectCaller = tagged "direct" []
  toJSON (CodeExecutionCaller version_ ident) = tagged (codeExecutionTag version_) ["tool_id" .= ident]
  toJSON (VersionedCaller _ fields) = Object fields

data ToolChangeReference
  = ToolReference !Text
  | MCPToolReference !Text !Text
  | MCPToolsetReference !Text
  deriving stock (Eq, Show)

instance ToJSON ToolChangeReference where
  toJSON (ToolReference name_) = tagged "tool_reference" ["name" .= name_]
  toJSON (MCPToolReference server name_) = tagged "mcp_tool_reference" ["server_name" .= server, "name" .= name_]
  toJSON (MCPToolsetReference server) = tagged "mcp_toolset_reference" ["server_name" .= server]

data WebSearch = WebSearch
  { version :: !WebSearchVersion,
    maxUses :: !(Maybe Natural),
    cacheControl :: !(Maybe CacheControl)
  }
  deriving stock (Eq, Show, Generic)

data WebSearchVersion = WebSearch20250305 | WebSearch20260209 | WebSearch20260318
  deriving stock (Eq, Show)

instance ToJSON Tool where
  toJSON (CustomTool tool) = object (clientToolFields tool)
  toJSON (ConfiguredTool tool (ToolLoading deferred callers)) =
    object (clientToolFields tool <> optional "defer_loading" deferred <> optional "allowed_callers" callers)
  toJSON (WebSearchTool tool) =
    tagged versionTag $
      ["name" .= ("web_search" :: Text)]
        <> optional "max_uses" (tool ^. #maxUses)
        <> optional "cache_control" (tool ^. #cacheControl)
    where
      versionTag = case tool ^. #version of
        WebSearch20250305 -> "web_search_20250305"
        WebSearch20260209 -> "web_search_20260209"
        WebSearch20260318 -> "web_search_20260318"
  toJSON (ToolSearchTool search cache) =
    tagged versionTag (["name" .= name_] <> optional "cache_control" cache)
    where
      (versionTag, name_) = case search of
        RegexSearch20251119 -> ("tool_search_tool_regex_20251119", "tool_search_tool_regex" :: Text)
        BM25Search20251119 -> ("tool_search_tool_bm25_20251119", "tool_search_tool_bm25")
  toJSON (CodeExecutionTool version_ cache) =
    tagged (codeExecutionTag version_) (["name" .= ("code_execution" :: Text)] <> optional "cache_control" cache)
  toJSON (VersionedTool tool) = toJSON tool

clientToolFields :: ClientTool -> [Pair]
clientToolFields tool =
  ["name" .= (tool ^. #name), "input_schema" .= (tool ^. #inputSchema)]
    <> optional "description" (tool ^. #description)
    <> optional "strict" (tool ^. #strict)
    <> optional "cache_control" (tool ^. #cacheControl)

data ToolChoice = AutoTool !Bool | AnyTool !Bool | NamedTool !Text !Bool | NoTool
  deriving stock (Eq, Show)

instance ToJSON ToolChoice where
  toJSON (AutoTool noParallel) = tagged "auto" ["disable_parallel_tool_use" .= noParallel | noParallel]
  toJSON (AnyTool noParallel) = tagged "any" ["disable_parallel_tool_use" .= noParallel | noParallel]
  toJSON (NamedTool name_ noParallel) =
    tagged "tool" (("name" .= name_) : ["disable_parallel_tool_use" .= noParallel | noParallel])
  toJSON NoTool = tagged "none" []

data ToolResultContent = ToolResultText !Text | ToolResultBlocks ![Object] | EmptyToolResult
  deriving stock (Eq, Show)

data ToolResult = ToolResult
  { toolUseId :: !Text,
    content :: !ToolResultContent,
    isError :: !(Maybe Bool),
    cacheControl :: !(Maybe CacheControl)
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON ToolResultContent where
  toJSON (ToolResultText text_) = toJSON text_
  toJSON (ToolResultBlocks blocks) = toJSON blocks
  toJSON EmptyToolResult = Null

instance ToJSON ToolResult where
  toJSON result =
    tagged "tool_result" $
      ["tool_use_id" .= (result ^. #toolUseId)]
        <> ["content" .= payload | let payload = result ^. #content, payload /= EmptyToolResult]
        <> optional "is_error" (result ^. #isError)
        <> optional "cache_control" (result ^. #cacheControl)

data Citation = Citation
  { location :: !CitationLocation,
    citationJSON :: !Value
  }
  deriving stock (Eq, Show, Generic)

data CitationLocation
  = CharacterRange !Text !Natural !(Maybe Text) !Natural !Natural
  | PageRange !Text !Natural !(Maybe Text) !Natural !Natural
  | BlockRange !Text !Natural !(Maybe Text) !Natural !Natural
  | WebLocation !Text !Text !(Maybe Text) !Text
  | UnknownCitation !Text
  deriving stock (Eq, Show)

instance FromJSON Citation where
  parseJSON raw = withObject "citation" decode raw
    where
      decode o = do
        tag <- o .: "type"
        let document constructor start end =
              constructor
                <$> o .: "cited_text"
                <*> o .: "document_index"
                <*> o .:? "document_title"
                <*> o .: start
                <*> o .: end
        observed <- case tag of
          "char_location" -> document CharacterRange "start_char_index" "end_char_index"
          "page_location" -> document PageRange "start_page_number" "end_page_number"
          "content_block_location" -> document BlockRange "start_block_index" "end_block_index"
          "web_search_result_location" ->
            WebLocation <$> o .: "cited_text" <*> o .: "url" <*> o .:? "title" <*> o .: "encrypted_index"
          other -> pure (UnknownCitation other)
        pure (Citation observed raw)

data WebSearchOutcome = WebSearchResults ![WebSearchResult] | WebSearchError !Text
  deriving stock (Eq, Show)

data WebSearchResult
  = SearchResult
      { url :: !Text,
        title :: !Text,
        encryptedContent :: !Text,
        pageAge :: !(Maybe Text)
      }
  | UnknownSearchResult !Text !Value
  deriving stock (Eq, Show, Generic)

instance FromJSON WebSearchResult where
  parseJSON raw =
    withObject
      "search result"
      ( \o ->
          o .: "type" >>= \case
            "web_search_result" -> SearchResult <$> o .: "url" <*> o .: "title" <*> o .: "encrypted_content" <*> o .:? "page_age"
            tag -> pure (UnknownSearchResult tag raw)
      )
      raw

instance FromJSON WebSearchOutcome where
  parseJSON raw = case raw of
    Array _ -> withArray "search results" (fmap WebSearchResults . traverse parseJSON . toList) raw
    _ ->
      withObject
        "search error"
        ( \o -> do
            tag <- o .: "type"
            if (tag :: Text) == "web_search_tool_result_error"
              then WebSearchError <$> o .: "error_code"
              else fail "expected web_search_tool_result_error"
        )
        raw

-- | The decoded view and original provider object travel together.
-- Replay uses the original JSON, retaining fields that this version cannot interpret.
data OutputBlock = OutputBlock
  { blockContent :: !BlockContent,
    blockJSON :: !Value
  }
  deriving stock (Eq, Show, Generic)

data BlockContent
  = OutputText !Text !(Maybe [Citation])
  | OutputThinking !Text !Text
  | RedactedThinking !Text
  | OutputToolUse !Text !Text !Value
  | OutputToolUseWithCaller !Text !Text !Value !ToolCaller
  | ServerToolUse !Text !Text !Value
  | WebSearchToolResult !Text !WebSearchOutcome
  | OutputToolSearchResult !Text !ToolSearchOutcome
  | OutputCodeExecutionResult !Text !CodeExecutionOutcome
  | OutputFallback !FallbackMarker
  | UnknownBlock !Text
  deriving stock (Eq, Show)

instance FromJSON OutputBlock where
  parseJSON raw = withObject "content block" decode raw
    where
      decode o = do
        tag <- o .: "type"
        let tool constructor = constructor <$> o .: "id" <*> o .: "name" <*> o .: "input"
        observed <- case tag of
          "text" -> OutputText <$> o .: "text" <*> o .:? "citations"
          "thinking" -> OutputThinking <$> o .: "thinking" <*> o .: "signature"
          "redacted_thinking" -> RedactedThinking <$> o .: "data"
          "tool_use" -> do
            caller <- o .:? "caller"
            case caller of
              Nothing -> tool OutputToolUse
              Just origin -> tool (\ident name_ input -> OutputToolUseWithCaller ident name_ input origin)
          "server_tool_use" -> tool ServerToolUse
          "web_search_tool_result" -> WebSearchToolResult <$> o .: "tool_use_id" <*> o .: "content"
          "tool_search_tool_result" -> OutputToolSearchResult <$> o .: "tool_use_id" <*> o .: "content"
          "code_execution_tool_result" -> executionResult o
          "bash_code_execution_tool_result" -> executionResult o
          "text_editor_code_execution_tool_result" -> executionResult o
          "fallback" -> OutputFallback <$> parseJSON raw
          other -> pure (UnknownBlock other)
        pure (OutputBlock observed raw)

instance ToJSON OutputBlock where
  toJSON = blockJSON

instance FromJSON ToolCaller where
  parseJSON = withObject "tool caller" $ \o ->
    o .: "type" >>= \case
      "direct" -> pure DirectCaller
      "code_execution_20250825" -> CodeExecutionCaller CodeExecution20250825 <$> o .: "tool_id"
      "code_execution_20260120" -> CodeExecutionCaller CodeExecution20260120 <$> o .: "tool_id"
      tag -> pure (VersionedCaller tag o)

data ToolSearchOutcome = ToolSearchMatches ![Text] | ToolSearchFailed !Text | UnknownToolSearchOutcome !Text !Object
  deriving stock (Eq, Show)

instance FromJSON ToolSearchOutcome where
  parseJSON = withObject "tool search result" $ \o ->
    let references = o .: "tool_references" >>= traverse (withObject "tool reference" (.: "tool_name"))
        failed = ToolSearchFailed <$> o .: "error_code"
     in o .: "type" >>= \case
          "tool_search_result" -> ToolSearchMatches <$> references
          "tool_search_tool_search_result" -> ToolSearchMatches <$> references
          "error" -> failed
          "tool_search_tool_result_error" -> failed
          tag -> pure (UnknownToolSearchOutcome tag o)

data CodeExecutionOutcome
  = CodeExecutionCompleted !Text !Text !Int ![Value]
  | CodeExecutionFailed !Text
  | UnknownCodeExecutionOutcome !Text !Object
  deriving stock (Eq, Show)

instance FromJSON CodeExecutionOutcome where
  parseJSON = withObject "code execution result" $ \o ->
    let completed = CodeExecutionCompleted <$> o .: "stdout" <*> o .: "stderr" <*> o .: "return_code" <*> o .: "content"
        failed = CodeExecutionFailed <$> o .: "error_code"
     in o .: "type" >>= \case
          "code_execution_result" -> completed
          "bash_code_execution_result" -> completed
          "code_execution_tool_result_error" -> failed
          "bash_code_execution_tool_result_error" -> failed
          "text_editor_code_execution_tool_result_error" -> failed
          tag -> pure (UnknownCodeExecutionOutcome tag o)

executionResult :: Object -> Parser BlockContent
executionResult o = OutputCodeExecutionResult <$> o .: "tool_use_id" <*> o .: "content"

data FallbackMarker = FallbackMarker
  { fromModel :: !Text,
    toModel :: !Text,
    triggerType :: !Text,
    category :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON FallbackMarker where
  parseJSON = withObject "fallback marker" $ \o -> do
    from <- o .: "from" >>= withObject "source model" (.: "model")
    to <- o .: "to" >>= withObject "fallback model" (.: "model")
    trigger <- o .: "trigger"
    withObject "fallback trigger" (\t -> FallbackMarker from to <$> t .: "type" <*> t .:? "category") trigger

instance ToJSON FallbackMarker where
  toJSON (FallbackMarker from to trigger reason) =
    tagged "fallback" ["from" .= object ["model" .= from], "to" .= object ["model" .= to], "trigger" .= tagged trigger (optional "category" reason)]

tagged :: Text -> [Pair] -> Value
tagged tag fields = object (("type" .= tag) : fields)

optional :: (ToJSON a) => Key -> Maybe a -> [Pair]
optional key = maybe [] (\item -> [key .= item])

instance FromJSON Speed where
  parseJSON = withText "speed" $ \case
    "standard" -> pure Standard
    "fast" -> pure Fast
    other -> pure (VersionedSpeed other)

instance FromJSON Effort where
  parseJSON = withText "effort" $ \case
    "low" -> pure Low
    "medium" -> pure Medium
    "high" -> pure High
    "xhigh" -> pure ExtraHigh
    "max" -> pure Maximum
    other -> pure (VersionedEffort other)

instance FromJSON OutputConfig where
  parseJSON = withObject "output config" $ \o -> do
    format <- o .:? "format"
    schema_ <- traverse (withObject "output format" (.: "schema")) format
    OutputConfig <$> o .:? "effort" <*> pure schema_

instance FromJSON Thinking where
  parseJSON = withObject "thinking" $ \o ->
    (o .: "type" :: Parser Text) >>= \case
      "adaptive" -> Adaptive <$> o .:? "display"
      "enabled" -> ManualBudget <$> o .: "budget_tokens" <*> o .:? "display"
      "disabled" -> pure ThinkingDisabled
      "between_tools" -> pure BetweenTools
      _ -> fail "unknown thinking mode"

instance FromJSON ThinkingDisplay where
  parseJSON = withText "thinking display" $ \case
    "summarized" -> pure Summarized
    "omitted" -> pure Omitted
    "updates" -> pure Updates
    _ -> fail "unknown thinking display"

instance FromJSON CacheControl where
  parseJSON = withObject "cache control" $ \o ->
    (o .: "type" :: Parser Text) >>= \case
      "ephemeral" -> Ephemeral <$> o .:? "ttl"
      _ -> fail "unknown cache control"

instance FromJSON CacheTTL where
  parseJSON = withText "cache TTL" $ \case
    "5m" -> pure FiveMinutes
    "1h" -> pure OneHour
    _ -> fail "unknown cache TTL"

instance FromJSON SystemPrompt where
  parseJSON raw = (SystemText <$> parseJSON raw) <|> (SystemBlocks <$> parseJSON raw)

instance FromJSON SystemBlock where
  parseJSON = withObject "system block" $ \o -> SystemBlock <$> o .: "text" <*> o .:? "cache_control"

instance FromJSON Tool where
  parseJSON = withObject "tool definition" (pure . VersionedTool)

instance FromJSON ToolChoice where
  parseJSON = withObject "tool choice" $ \o -> do
    noParallel <- o .:? "disable_parallel_tool_use" .!= False
    (o .: "type" :: Parser Text) >>= \case
      "auto" -> pure (AutoTool noParallel)
      "any" -> pure (AnyTool noParallel)
      "tool" -> NamedTool <$> o .: "name" <*> pure noParallel
      "none" -> pure NoTool
      _ -> fail "unknown tool choice"

instance FromJSON Compaction where
  parseJSON = withObject "context management edit" $ \o -> do
    trigger <- o .:? "trigger"
    threshold <- traverse (withObject "compaction trigger" (.: "value")) trigger
    (o .: "type" :: Parser Text) >>= \case
      "compact_20260112" -> Compaction <$> o .:? "instructions" <*> o .:? "pause_after_compaction" <*> pure threshold
      _ -> fail "unknown context management edit"

instance FromJSON Fallbacks where
  parseJSON (String "default") = pure DefaultFallbacks
  parseJSON raw = FallbackModels <$> parseJSON raw

instance FromJSON FallbackModel where
  parseJSON = withObject "fallback model" $ \o ->
    FallbackModel <$> o .: "model" <*> o .:? "max_tokens" <*> o .:? "output_config" <*> o .:? "speed" <*> o .:? "thinking"

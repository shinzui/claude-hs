-- | Request options and content variants shared by Messages and SSE.
module Claude.Messages.Features
  ( MessageFeatures (..),
    defaultMessageFeatures,
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
    blockContent,
    blockJSON,
  )
where

import Control.Lens ((^.))
import Data.Aeson (FromJSON (..), Key, Object, ToJSON (..), Value (..), object, withArray, withObject, (.:), (.:?), (.=))
import Data.Aeson.Types (Pair)
import Data.Foldable (toList)
import Data.Generics.Labels ()
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

data Speed = Standard | Fast
  deriving stock (Eq, Show)

instance ToJSON Speed where
  toJSON Standard = "standard"
  toJSON Fast = "fast"

data Effort = Low | Medium | High | ExtraHigh | Maximum
  deriving stock (Eq, Show)

instance ToJSON Effort where
  toJSON Low = "low"
  toJSON Medium = "medium"
  toJSON High = "high"
  toJSON ExtraHigh = "xhigh"
  toJSON Maximum = "max"

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

data Tool = CustomTool !ClientTool | WebSearchTool !WebSearch | VersionedTool !Object
  deriving stock (Eq, Show)

data ClientTool = ClientTool
  { name :: !Text,
    description :: !(Maybe Text),
    inputSchema :: !Object,
    strict :: !(Maybe Bool),
    cacheControl :: !(Maybe CacheControl)
  }
  deriving stock (Eq, Show, Generic)

data WebSearch = WebSearch
  { version :: !WebSearchVersion,
    maxUses :: !(Maybe Natural),
    cacheControl :: !(Maybe CacheControl)
  }
  deriving stock (Eq, Show, Generic)

data WebSearchVersion = WebSearch20250305 | WebSearch20260209 | WebSearch20260318
  deriving stock (Eq, Show)

instance ToJSON Tool where
  toJSON (CustomTool tool) =
    object $
      ["name" .= (tool ^. #name), "input_schema" .= (tool ^. #inputSchema)]
        <> optional "description" (tool ^. #description)
        <> optional "strict" (tool ^. #strict)
        <> optional "cache_control" (tool ^. #cacheControl)
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
  toJSON (VersionedTool tool) = toJSON tool

data ToolChoice = AutoTool !Bool | AnyTool !Bool | NamedTool !Text !Bool | NoTool
  deriving stock (Eq, Show)

instance ToJSON ToolChoice where
  toJSON (AutoTool noParallel) = tagged "auto" ["disable_parallel_tool_use" .= noParallel | noParallel]
  toJSON (AnyTool noParallel) = tagged "any" ["disable_parallel_tool_use" .= noParallel | noParallel]
  toJSON (NamedTool name_ noParallel) =
    tagged "tool" (("name" .= name_) : ["disable_parallel_tool_use" .= noParallel | noParallel])
  toJSON NoTool = tagged "none" []

data ToolResultContent = ToolResultText !Text | ToolResultBlocks ![Object]
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

instance ToJSON ToolResult where
  toJSON result =
    tagged "tool_result" $
      ["tool_use_id" .= (result ^. #toolUseId), "content" .= (result ^. #content)]
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
  | ServerToolUse !Text !Text !Value
  | WebSearchToolResult !Text !WebSearchOutcome
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
          "tool_use" -> tool OutputToolUse
          "server_tool_use" -> tool ServerToolUse
          "web_search_tool_result" -> WebSearchToolResult <$> o .: "tool_use_id" <*> o .: "content"
          other -> pure (UnknownBlock other)
        pure (OutputBlock observed raw)

tagged :: Text -> [Pair] -> Value
tagged tag fields = object (("type" .= tag) : fields)

optional :: (ToJSON a) => Key -> Maybe a -> [Pair]
optional key = maybe [] (\item -> [key .= item])

-- | Billing evidence shared by complete messages and cumulative stream deltas.
module Claude.Messages.Usage
  ( UsageEvidence (..),
    ServerToolCounts (..),
    OutputTokenDetails (..),
    UsageIteration (..),
    mergeUsageEvidence,
  )
where

import Claude.Messages.Features (Speed)
import Control.Applicative ((<|>))
import Data.Aeson (FromJSON (..), Object, withObject, (.:), (.:?))
import Data.Text (Text)
import GHC.Generics (Generic)
import Numeric.Natural (Natural)

data UsageEvidence = UsageEvidence
  { inferenceGeography :: !(Maybe Text),
    serviceTier :: !(Maybe Text),
    observedSpeed :: !(Maybe Speed),
    outputTokensDetails :: !(Maybe OutputTokenDetails),
    iterations :: !(Maybe [UsageIteration]),
    serverToolCounts :: !(Maybe ServerToolCounts)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON UsageEvidence where
  parseJSON = withObject "usage evidence" $ \o ->
    UsageEvidence
      <$> o .:? "inference_geo"
      <*> o .:? "service_tier"
      <*> o .:? "speed"
      <*> o .:? "output_tokens_details"
      <*> o .:? "iterations"
      <*> o .:? "server_tool_use"

data ServerToolCounts = ServerToolCounts
  { webSearchRequests :: !(Maybe Natural),
    webFetchRequests :: !(Maybe Natural),
    toolSearchRequests :: !(Maybe Natural),
    codeExecutionRequests :: !(Maybe Natural)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON ServerToolCounts where
  parseJSON = withObject "server tool counts" $ \o ->
    ServerToolCounts
      <$> o .:? "web_search_requests"
      <*> o .:? "web_fetch_requests"
      <*> o .:? "tool_search_requests"
      <*> o .:? "code_execution_requests"

newtype OutputTokenDetails = OutputTokenDetails
  { thinkingTokens :: Maybe Natural
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON OutputTokenDetails where
  parseJSON = withObject "output token details" $ \o -> OutputTokenDetails <$> o .:? "thinking_tokens"

data UsageIteration = UsageIteration
  { iterationType :: !Text,
    iterationModel :: !(Maybe Text),
    iterationInputTokens :: !(Maybe Natural),
    iterationOutputTokens :: !(Maybe Natural),
    iterationCacheCreationInputTokens :: !(Maybe Natural),
    iterationCacheReadInputTokens :: !(Maybe Natural),
    iterationJSON :: !Object
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON UsageIteration where
  parseJSON = withObject "usage iteration" $ \o ->
    UsageIteration
      <$> o .: "type"
      <*> o .:? "model"
      <*> o .:? "input_tokens"
      <*> o .:? "output_tokens"
      <*> o .:? "cache_creation_input_tokens"
      <*> o .:? "cache_read_input_tokens"
      <*> pure o

mergeUsageEvidence :: UsageEvidence -> UsageEvidence -> UsageEvidence
mergeUsageEvidence old new =
  UsageEvidence
    { inferenceGeography = inferenceGeography new <|> inferenceGeography old,
      serviceTier = serviceTier new <|> serviceTier old,
      observedSpeed = observedSpeed new <|> observedSpeed old,
      outputTokensDetails = mergeWith mergeOutput (outputTokensDetails old) (outputTokensDetails new),
      iterations = iterations new <|> iterations old,
      serverToolCounts = mergeWith mergeTools (serverToolCounts old) (serverToolCounts new)
    }
  where
    mergeWith merge (Just previous) (Just latest) = Just (merge previous latest)
    mergeWith _ previous latest = latest <|> previous
    mergeOutput previous latest = OutputTokenDetails (thinkingTokens latest <|> thinkingTokens previous)
    mergeTools previous latest =
      ServerToolCounts
        { webSearchRequests = webSearchRequests latest <|> webSearchRequests previous,
          webFetchRequests = webFetchRequests latest <|> webFetchRequests previous,
          toolSearchRequests = toolSearchRequests latest <|> toolSearchRequests previous,
          codeExecutionRequests = codeExecutionRequests latest <|> codeExecutionRequests previous
        }

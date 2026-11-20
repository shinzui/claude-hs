-- | Asynchronous Message Batches and scoped JSON Lines result consumption.
module Claude.Batches
  ( BatchId,
    batchId,
    batchIdText,
    CustomId,
    mkCustomId,
    customIdText,
    BatchItem (..),
    Batch (..),
    ProcessingStatus (..),
    RequestCounts (..),
    BatchPage (..),
    BatchCursor (..),
    BatchListOptions (..),
    BatchResult (..),
    BatchOutcome (..),
    createBatch,
    retrieveBatch,
    listBatches,
    cancelBatch,
    consumeBatchResults,
  )
where

import Claude.Client
import Claude.Internal.Http (decodeResponse, jsonRequest, redactApiError, runRequest)
import Claude.Internal.Request qualified as Request
import Claude.Messages (MessageRequest, MessageResponse)
import Control.Lens ((^.))
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (throwE)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, withText, (.:), (.:?), (.=))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BSC
import Data.ByteString.Lazy qualified as LBS
import Data.Char (isAlphaNum, isAscii)
import Data.Generics.Labels ()
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding (encodeUtf8)
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Network.HTTP.Types (Query)
import Numeric.Natural (Natural)

newtype BatchId = BatchId Text
  deriving stock (Eq, Ord, Show)

batchId :: Text -> Maybe BatchId
batchId text
  | validId text = Just (BatchId text)
  | otherwise = Nothing

batchIdText :: BatchId -> Text
batchIdText (BatchId text) = text

instance FromJSON BatchId where
  parseJSON = withText "batch ID" $ maybe (fail "invalid batch ID") pure . batchId

newtype CustomId = CustomId Text
  deriving stock (Eq, Ord, Show)
  deriving newtype (ToJSON)

mkCustomId :: Text -> Maybe CustomId
mkCustomId text
  | validId text && Text.length text <= 64 = Just (CustomId text)
  | otherwise = Nothing

customIdText :: CustomId -> Text
customIdText (CustomId text) = text

instance FromJSON CustomId where
  parseJSON = withText "custom ID" $ maybe (fail "invalid custom ID") pure . mkCustomId

validId :: Text -> Bool
validId text =
  not (Text.null text) && Text.all (\c -> isAscii c && (isAlphaNum c || c == '-' || c == '_')) text

data BatchItem = BatchItem
  { customId :: !CustomId,
    params :: !MessageRequest
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON BatchItem where
  toJSON item = object ["custom_id" .= (item ^. #customId), "params" .= (item ^. #params)]

data ProcessingStatus = InProgress | Canceling | Ended | UnknownProcessingStatus !Text
  deriving stock (Eq, Show)

instance FromJSON ProcessingStatus where
  parseJSON =
    withText "processing_status" $
      pure . \case
        "in_progress" -> InProgress
        "canceling" -> Canceling
        "ended" -> Ended
        other -> UnknownProcessingStatus other

data RequestCounts = RequestCounts
  { processing :: !Natural,
    succeeded :: !Natural,
    errored :: !Natural,
    canceled :: !Natural,
    expired :: !Natural
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON RequestCounts where
  parseJSON = withObject "batch request counts" $ \o ->
    RequestCounts <$> o .: "processing" <*> o .: "succeeded" <*> o .: "errored" <*> o .: "canceled" <*> o .: "expired"

data Batch = Batch
  { id :: !BatchId,
    processingStatus :: !ProcessingStatus,
    requestCounts :: !RequestCounts,
    createdAt :: !UTCTime,
    expiresAt :: !UTCTime,
    endedAt :: !(Maybe UTCTime),
    cancelInitiatedAt :: !(Maybe UTCTime),
    archivedAt :: !(Maybe UTCTime),
    resultsUrl :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON Batch where
  parseJSON = withObject "batch" $ \o ->
    Batch
      <$> o .: "id"
      <*> o .: "processing_status"
      <*> o .: "request_counts"
      <*> o .: "created_at"
      <*> o .: "expires_at"
      <*> o .:? "ended_at"
      <*> o .:? "cancel_initiated_at"
      <*> o .:? "archived_at"
      <*> o .:? "results_url"

data BatchPage = BatchPage
  { batches :: ![Batch],
    firstId :: !(Maybe BatchId),
    lastId :: !(Maybe BatchId),
    hasMore :: !Bool
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON BatchPage where
  parseJSON = withObject "batch page" $ \o ->
    BatchPage <$> o .: "data" <*> o .:? "first_id" <*> o .:? "last_id" <*> o .: "has_more"

data BatchCursor = After !BatchId | Before !BatchId
  deriving stock (Eq, Show)

data BatchListOptions = BatchListOptions
  { cursor :: !(Maybe BatchCursor),
    limit :: !(Maybe Natural)
  }
  deriving stock (Eq, Show, Generic)

data BatchResult = BatchResult
  { customId :: !CustomId,
    outcome :: !BatchOutcome
  }
  deriving stock (Eq, Generic)

data BatchOutcome
  = BatchSucceeded !MessageResponse
  | BatchErrored !ApiError
  | BatchCanceled
  | BatchExpired
  deriving stock (Eq)

instance FromJSON BatchResult where
  parseJSON = withObject "batch result line" $ \o ->
    BatchResult <$> o .: "custom_id" <*> o .: "result"

instance FromJSON BatchOutcome where
  parseJSON = withObject "batch outcome" $ \o ->
    o .: "type" >>= \case
      "succeeded" -> BatchSucceeded <$> o .: "message"
      "errored" -> do
        envelope <- o .: "error"
        BatchErrored <$> withObject "error envelope" (.: "error") envelope
      "canceled" -> pure BatchCanceled
      "expired" -> pure BatchExpired
      (_ :: Text) -> fail "unknown batch outcome"

batchRoot :: ByteString
batchRoot = "/v1/messages/batches"

batchRoute :: BatchId -> ByteString
batchRoute ident = batchRoot <> "/" <> encodeUtf8 (batchIdText ident)

createBatch :: Client -> RequestOptions -> NonEmpty BatchItem -> IO (Either ClientError (Response Batch))
createBatch client options items
  | Set.size ids /= NonEmpty.length items = pure (Left (InvalidRequest "Batch custom IDs must be unique"))
  | otherwise = case traverse (Request.validateMessages client Request.Batch . toJSON . (^. #params)) items of
      Left err -> pure (Left err)
      Right _ -> jsonRequest client "POST" batchRoot [] options (Just (object ["requests" .= items]))
  where
    ids = Set.fromList (map (^. #customId) (NonEmpty.toList items))

retrieveBatch :: Client -> RequestOptions -> BatchId -> IO (Either ClientError (Response Batch))
retrieveBatch client options ident = jsonRequest client "GET" (batchRoute ident) [] options Nothing

listBatches :: Client -> RequestOptions -> BatchListOptions -> IO (Either ClientError (Response BatchPage))
listBatches client options page
  | any (\n -> n < 1 || n > 1000) (page ^. #limit) = pure (Left (InvalidRequest "Batch list limit must be between 1 and 1000"))
  | otherwise = jsonRequest client "GET" batchRoot query options Nothing
  where
    query :: Query
    query = case page ^. #cursor of
      Just (After ident) -> ("after_id", Just (encodeUtf8 (batchIdText ident))) : limits
      Just (Before ident) -> ("before_id", Just (encodeUtf8 (batchIdText ident))) : limits
      Nothing -> limits
    limits = [("limit", Just (BSC.pack (show n))) | Just n <- [page ^. #limit]]

cancelBatch :: Client -> RequestOptions -> BatchId -> IO (Either ClientError (Response Batch))
cancelBatch client options ident = jsonRequest client "POST" (batchRoute ident <> "/cancel") [] options Nothing

-- | Deliver each result before reading the next line. Correlate by custom ID.
-- An HTTP or decoding failure may follow already delivered results.
-- The documented endpoint is constructed from the batch ID on the client origin.
consumeBatchResults ::
  Client ->
  RequestOptions ->
  BatchId ->
  (BatchResult -> IO ()) ->
  IO (Either ClientError (Response ()))
consumeBatchResults client options ident consume =
  runRequest client "GET" (batchRoute ident <> "/results") [] options "application/binary" Nothing $ \meta readBody -> do
    let deliver fragments = do
          result <- either throwE pure (decodeResponse meta (LBS.fromChunks (reverse fragments)))
          liftIO $ consume $ case result of
            BatchResult requestId_ (BatchErrored err) -> BatchResult requestId_ (BatchErrored (redactApiError client err))
            other -> other
        feed fragments chunk
          | BS.null chunk = do
              next <- readBody
              if BS.null next
                then if null fragments then pure () else deliver fragments
                else feed fragments next
          | otherwise = case BS.break (== 10) chunk of
              (prefix, rest)
                | BS.null rest -> feed (prefix : fragments) BS.empty
                | otherwise -> deliver (prefix : fragments) >> feed [] (BS.drop 1 rest)
    feed [] BS.empty

module BatchesSpec (run) where

import Claude.Batches
import Claude.Client
import Claude.Messages (OutputTokenDetails (..), RequestControls (..), StopDetails (..), defaultRequestControls, responseText, withRequestControls)
import Control.Concurrent (newEmptyMVar, putMVar, takeMVar)
import Control.Lens ((^.))
import Control.Monad (void)
import Data.Aeson (Value (..), eitherDecode, encode, object, toJSON, (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Builder (lazyByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Time (UTCTime)
import FeaturesSpec (enrichedConversation, enrichedOptions, thinkingBlock)
import MessagesSpec (messageWithEvidence, sampleRequest)
import Network.HTTP.Types (status200)
import Network.Wai qualified as Wai
import Support.Server

run :: IO ()
run = do
  lifecycle
  incrementalResults
  putStrLn "Batches: enriched submission, cursors, cancellation and incremental mixed outcomes passed"

withBatchId :: (BatchId -> IO a) -> IO a
withBatchId action = maybe (fail "invalid fixture batch ID") action (batchId "msgbatch_fixture")

lifecycle :: IO ()
lifecycle = withBatchId $ \ident -> do
  requests <- newIORef []
  request <- withRequestControls defaultRequestControls {containerId = Just "container_batch", inferenceGeo = Just "us"} <$> sampleRequest enrichedConversation
  a <- maybe (fail "invalid alpha ID") pure (mkCustomId "alpha")
  b <- maybe (fail "invalid beta ID") pure (mkCustomId "beta")
  let running = batchFixture "in_progress" False
      canceling = batchFixture "canceling" True
      ended = batchFixture "ended" True
      itemJson itemId = object ["custom_id" .= (itemId :: Text), "params" .= toJSON request]
      app req send = do
        body <- Wai.strictRequestBody req
        case (Wai.requestMethod req, Wai.pathInfo req) of
          ("POST", ["v1", "messages", "batches"]) -> do
            assertEqual "enriched params" (Right (object ["requests" .= [itemJson "alpha", itemJson "beta"]])) (eitherDecode body)
            assertEqual "shared beta header" (Just "fast-mode-2026-02-01") (lookup "anthropic-beta" (Wai.requestHeaders req))
            send (json status200 [] running)
          ("GET", ["v1", "messages", "batches", "msgbatch_fixture"]) ->
            send (json status200 [] ended)
          ("GET", ["v1", "messages", "batches"]) -> do
            modifyIORef' requests (<> [Wai.queryString req])
            send (json status200 [] (object ["data" .= [running], "has_more" .= True, "first_id" .= batchIdText ident, "last_id" .= batchIdText ident]))
          ("POST", ["v1", "messages", "batches", "msgbatch_fixture", "cancel"]) ->
            send (json status200 [] canceling)
          route -> fail ("Unexpected batch route " <> show route)
  withClient app $ \client -> do
    Response _ created <- createBatch client enrichedOptions (BatchItem a request :| [BatchItem b request]) >>= expectRight
    assertEqual "running batch" (ident, InProgress, Nothing, Nothing) (created ^. #id, created ^. #processingStatus, created ^. #resultsUrl, created ^. #endedAt)
    assertEqual "decoded ISO timestamp" (read "2026-11-20 19:35:56.25 UTC" :: UTCTime) (created ^. #createdAt)
    mapM_
      ( \cursor_ -> do
          Response _ page <- listBatches client defaultRequestOptions (BatchListOptions (Just cursor_) (Just 7)) >>= expectRight
          assertEqual "cursor metadata" (True, Just ident, Just ident, [created]) (page ^. #hasMore, page ^. #firstId, page ^. #lastId, page ^. #batches)
      )
      [After ident, Before ident]
    Response _ cancelingBatch <- cancelBatch client defaultRequestOptions ident >>= expectRight
    assertEqual "cancel requested" Canceling (cancelingBatch ^. #processingStatus)
    assert "cancel timestamp" (cancelingBatch ^. #cancelInitiatedAt /= Nothing)
    Response _ final <- retrieveBatch client defaultRequestOptions ident >>= expectRight
    assertEqual "fresh status" Ended (final ^. #processingStatus)
    assertEqual "final request counts" (RequestCounts 0 1 1 1 1) (final ^. #requestCounts)
  readIORef requests
    >>= assertEqual
      "pagination query in both directions"
      [[("after_id", Just "msgbatch_fixture"), ("limit", Just "7")], [("before_id", Just "msgbatch_fixture"), ("limit", Just "7")]]
  let noDispatch = withClient (\_ _ -> fail "Invalid batch dispatched")
  noDispatch $ \client -> do
    createBatch client defaultRequestOptions (BatchItem a request :| [BatchItem a request]) >>= \case
      Left (InvalidRequest _) -> pure ()
      _ -> fail "Expected duplicate ID error"
    listBatches client defaultRequestOptions (BatchListOptions Nothing (Just 0)) >>= \case
      Left (InvalidRequest _) -> pure ()
      _ -> fail "Expected out-of-range list limit"
  assertEqual "invalid custom ID" Nothing (mkCustomId "bad/id")

batchFixture :: Text -> Bool -> Value
batchFixture state cancelRequested =
  object
    [ "id" .= ("msgbatch_fixture" :: Text),
      "type" .= ("message_batch" :: Text),
      "created_at" .= ("2026-11-20T19:35:56.25Z" :: Text),
      "expires_at" .= ("2026-11-21T19:35:56Z" :: Text),
      "processing_status" .= state,
      "ended_at" .= (if state == "ended" then String "2026-11-20T19:36:56Z" else Null),
      "cancel_initiated_at" .= (if cancelRequested then String "2026-11-20T19:36:01Z" else Null),
      "archived_at" .= Null,
      "results_url" .= (if state == "ended" then String "https://off-origin.invalid/results.jsonl" else Null),
      "request_counts"
        .= object
          [ "processing" .= (if state == "ended" then 0 :: Int else 4),
            "succeeded" .= done,
            "errored" .= done,
            "canceled" .= done,
            "expired" .= done
          ]
    ]
  where
    done = if state == "ended" then 1 :: Int else 0

incrementalResults :: IO ()
incrementalResults = withBatchId $ \ident -> do
  let outcome custom tag fields = encode (object ["custom_id" .= (custom :: Text), "result" .= object (("type" .= (tag :: Text)) : fields)])
      first = outcome "delta" "expired" []
      second = outcome "gamma" "canceled" []
      third =
        outcome
          "beta"
          "errored"
          ["error" .= object ["type" .= ("error" :: Text), "error" .= object ["type" .= ("overloaded_error" :: Text), "message" .= ("echo loopback-secret" :: Text)]]]
      fourth =
        outcome
          "alpha"
          "succeeded"
          [ "message"
              .= withBlocks messageWithEvidence [thinkingBlock "" "batch-signature", object ["type" .= ("text" :: Text), "text" .= ("café" :: Text)]]
          ]
      exercise malformed = do
        gate <- newEmptyMVar
        results <- newIORef []
        let app req send = do
              assertEqual "configured results route" ("GET", "/v1/messages/batches/msgbatch_fixture/results") (Wai.requestMethod req, Wai.rawPathInfo req)
              assertEqual "results accept" (Just "application/binary") (lookup "accept" (Wai.requestHeaders req))
              send $ Wai.responseStream status200 [("request-id", "req_batch"), ("content-type", "application/x-jsonlines")] $ \write flush -> do
                write (lazyByteString (LBS.take 9 first)) >> flush
                write (lazyByteString (LBS.drop 9 first <> "\r\n")) >> flush
                takeMVar gate
                let rest = if malformed then "malformed\n" else second <> "\n" <> third <> "\n" <> fourth
                write (lazyByteString rest)
                flush
        withClient app $ \client -> do
          result <- consumeBatchResults client defaultRequestOptions ident $ \item -> do
            modifyIORef' results (item :)
            if customIdText (item ^. #customId) == "delta" then putMVar gate () else pure ()
          if malformed
            then case result of
              Left (DecodeError meta _) -> assertEqual "malformed line request ID" (Just "req_batch") (meta ^. #requestId)
              _ -> fail "Expected malformed JSON line"
            else void (expectRight result)
        reverse <$> readIORef results
  good <- exercise False
  assertEqual "results correlate by custom ID" ["delta", "gamma", "beta", "alpha"] (map (customIdText . (^. #customId)) good)
  case map (^. #outcome) good of
    [BatchExpired, BatchCanceled, BatchErrored (ApiError "overloaded_error" "echo [redacted]"), BatchSucceeded result] -> do
      assertEqual "batch message uses shared response codec" "café" (responseText result)
      assertEqual "batch stop details" (Just (RefusalDetails (Just "other") (Just "declined") Nothing)) (result ^. #stopDetails)
      assertEqual "batch reasoning" (Just (OutputTokenDetails (Just 5))) (result ^. #usage . #usageEvidence . #outputTokensDetails)
    _ -> fail "Expected all four batch outcomes"
  partial <- exercise True
  assertEqual "first line delivered before later failure" ["delta"] (map (customIdText . (^. #customId)) partial)

withBlocks :: Value -> [Value] -> Value
withBlocks (Object fields) blocks = Object (KeyMap.insert "content" (toJSON blocks) fields)
withBlocks other _ = other

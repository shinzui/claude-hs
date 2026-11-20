module Claude.Internal.Http
  ( Client,
    ClientConfig (..),
    defaultClientConfig,
    newClient,
    RequestOptions (..),
    defaultRequestOptions,
    Response (..),
    ResponseMetadata (..),
    ApiError (..),
    ClientError (..),
    TransportFailure (..),
    BodyReader,
    runRequest,
    jsonRequest,
    decodeResponse,
    redactApiError,
    clientApiVersion,
  )
where

import Control.Exception (bracket, try)
import Control.Lens ((^.))
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import Data.Aeson (FromJSON (..), Value, eitherDecode, encode, withObject, (.:))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding (decodeUtf8Lenient)
import GHC.Generics (Generic)
import Network.HTTP.Client qualified as HTTP
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types (HeaderName, Method, Query, RequestHeaders, hAccept, hContentType, renderQuery, statusCode)

data Client = Client !HTTP.Manager !HTTP.Request

data ClientConfig = ClientConfig
  { apiKey :: !ByteString,
    endpoint :: !String,
    timeoutMicros :: !(Maybe Int),
    apiVersion :: !(Maybe ByteString)
  }
  deriving stock (Generic)

defaultClientConfig :: ByteString -> ClientConfig
defaultClientConfig key = ClientConfig key "https://api.anthropic.com" (Just 60000000) (Just "2026-10-21")

newClient :: ClientConfig -> IO (Either ClientError Client)
newClient config
  | BS.null (config ^. #apiKey) = pure (Left (InvalidRequest "An API key is required"))
  | maybe False (<= 0) (config ^. #timeoutMicros) = pure (Left (InvalidRequest "The response timeout must be positive"))
  | otherwise = do
      parsed <- try (HTTP.parseRequest (config ^. #endpoint))
      case parsed of
        Left (_ :: HTTP.HttpException) -> pure (Left (InvalidRequest "Invalid HTTP endpoint"))
        Right base
          | not (BS.null (HTTP.queryString base)) || isJust (lookup "authorization" (HTTP.requestHeaders base)) ->
              pure (Left (InvalidRequest "The endpoint must use a host and optional path prefix"))
          | otherwise -> do
              manager <- HTTP.newManager tlsManagerSettings {HTTP.managerRetryableException = const False}
              pure . Right . Client manager $
                base
                  { HTTP.redirectCount = 0,
                    HTTP.checkResponse = \_ _ -> pure (),
                    HTTP.cookieJar = Nothing,
                    HTTP.responseTimeout = maybe HTTP.responseTimeoutNone HTTP.responseTimeoutMicro (config ^. #timeoutMicros),
                    HTTP.requestHeaders =
                      [("x-api-key", config ^. #apiKey)]
                        <> [("anthropic-version", version) | Just version <- [config ^. #apiVersion]]
                  }

data RequestOptions = RequestOptions
  { betaFeatures :: ![ByteString],
    extraHeaders :: !RequestHeaders
  }
  deriving stock (Generic)

defaultRequestOptions :: RequestOptions
defaultRequestOptions = RequestOptions [] []

data ResponseMetadata = ResponseMetadata
  { requestId :: !(Maybe ByteString),
    retryAfter :: !(Maybe ByteString),
    status :: !Int,
    gatewayRequestId :: !(Maybe ByteString),
    cloudflareRay :: !(Maybe ByteString)
  }
  deriving stock (Eq, Generic)

data Response a = Response
  { metadata :: !ResponseMetadata,
    value :: !a
  }
  deriving stock (Eq, Generic)

data ApiError = ApiError
  { errorType :: !Text,
    message :: !Text
  }
  deriving stock (Eq, Generic)

instance FromJSON ApiError where
  parseJSON = withObject "API error" $ \o -> ApiError <$> o .: "type" <*> o .: "message"

data TransportFailure = ConnectTimeout | ReadTimeout | ConnectionFailed | Disconnected | HttpFailure
  deriving stock (Eq, Show)

data ClientError
  = InvalidRequest !Text
  | TransportError !(Maybe ResponseMetadata) !TransportFailure
  | ApiStatusError !ResponseMetadata !(Maybe ApiError)
  | DecodeError !ResponseMetadata !Text
  | StreamApiError !ResponseMetadata !ApiError
  deriving stock (Eq)

-- Keep request headers, provider-controlled values and decode input out of logs.
instance Show ClientError where
  show = \case
    InvalidRequest _ -> "InvalidRequest"
    TransportError _ kind -> "TransportError " <> show kind
    ApiStatusError meta _ -> "ApiStatusError " <> show (meta ^. #status)
    DecodeError meta _ -> "DecodeError (HTTP " <> show (meta ^. #status) <> ")"
    StreamApiError _ _ -> "StreamApiError"

type BodyReader = ExceptT ClientError IO ByteString

runRequest ::
  Client ->
  Method ->
  ByteString ->
  Query ->
  RequestOptions ->
  ByteString ->
  Maybe Value ->
  (ResponseMetadata -> BodyReader -> ExceptT ClientError IO a) ->
  IO (Either ClientError (Response a))
runRequest client@(Client manager base) method route query options accept body consume
  | any ((`elem` reservedHeaders) . fst) (options ^. #extraHeaders) =
      pure (Left (InvalidRequest "A request header is owned by the client"))
  | otherwise = bracket (try (HTTP.responseOpen request manager)) close $ \case
      Left exc -> pure (Left (TransportError Nothing (classify exc)))
      Right response -> runExceptT $ do
        let headers = HTTP.responseHeaders response
            meta =
              ResponseMetadata
                (lookup "request-id" headers)
                (lookup "retry-after" headers)
                (statusCode (HTTP.responseStatus response))
                (lookup "x-request-id" headers)
                (lookup "cf-ray" headers)
            readBody = ExceptT $ either (Left . TransportError (Just meta) . classify) Right <$> try (HTTP.brRead (HTTP.responseBody response))
        if meta ^. #status >= 200 && meta ^. #status < 300
          then Response meta <$> consume meta readBody
          else do
            -- The status and request ID remain available if the peer cuts off the error body.
            decoded <- ExceptT $ Right <$> runExceptT (collectBody readBody)
            throwE (ApiStatusError meta (either (const Nothing) (apiErrorFromBody client) decoded))
  where
    request =
      base
        { HTTP.method = method,
          HTTP.path = BS.dropWhileEnd (== 47) (HTTP.path base) <> route,
          HTTP.queryString = renderQuery True query,
          HTTP.requestHeaders =
            HTTP.requestHeaders base
              <> [(hAccept, accept)]
              <> [(hContentType, "application/json") | isJust body]
              <> [("anthropic-beta", BS.intercalate "," betas) | let betas = options ^. #betaFeatures, not (null betas)]
              <> options ^. #extraHeaders,
          HTTP.requestBody = maybe (HTTP.RequestBodyBS "") (HTTP.RequestBodyLBS . encode) body
        }
    close = either (const (pure ())) HTTP.responseClose

reservedHeaders :: [HeaderName]
reservedHeaders =
  [ "x-api-key",
    "authorization",
    "proxy-authorization",
    "anthropic-version",
    "anthropic-beta",
    "host",
    "content-length",
    "transfer-encoding",
    "connection",
    "expect",
    "upgrade",
    "te",
    "trailer",
    hAccept,
    hContentType
  ]

classify :: HTTP.HttpException -> TransportFailure
classify (HTTP.HttpExceptionRequest _ exc) = case exc of
  HTTP.ConnectionTimeout -> ConnectTimeout
  HTTP.ResponseTimeout -> ReadTimeout
  HTTP.ConnectionFailure _ -> ConnectionFailed
  HTTP.NoResponseDataReceived -> Disconnected
  HTTP.ConnectionClosed -> Disconnected
  HTTP.ResponseBodyTooShort _ _ -> Disconnected
  _ -> HttpFailure
classify _ = HttpFailure

clientApiVersion :: Client -> Maybe ByteString
clientApiVersion (Client _ base) = lookup "anthropic-version" (HTTP.requestHeaders base)

redactApiError :: Client -> ApiError -> ApiError
redactApiError (Client _ base) (ApiError kind detail) =
  ApiError (redact kind) (redact detail)
  where
    key = maybe "" decodeUtf8Lenient (lookup "x-api-key" (HTTP.requestHeaders base))
    redact = if Text.null key then id else Text.replace key "[redacted]"

apiErrorFromBody :: Client -> LBS.ByteString -> Maybe ApiError
apiErrorFromBody client body = do
  ErrorEnvelope err <- either (const Nothing) Just (eitherDecode body)
  pure (redactApiError client err)

newtype ErrorEnvelope = ErrorEnvelope ApiError

instance FromJSON ErrorEnvelope where
  parseJSON = withObject "error envelope" $ \o -> ErrorEnvelope <$> o .: "error"

collectBody :: BodyReader -> ExceptT ClientError IO LBS.ByteString
collectBody readBody = go []
  where
    go chunks = do
      chunk <- readBody
      if BS.null chunk then pure (LBS.fromChunks (reverse chunks)) else go (chunk : chunks)

decodeResponse :: (FromJSON a) => ResponseMetadata -> LBS.ByteString -> Either ClientError a
decodeResponse meta = either (Left . DecodeError meta . Text.pack) Right . eitherDecode

jsonRequest ::
  (FromJSON a) =>
  Client ->
  Method ->
  ByteString ->
  Query ->
  RequestOptions ->
  Maybe Value ->
  IO (Either ClientError (Response a))
jsonRequest client method route query options body =
  runRequest client method route query options "application/json" body $ \meta readBody ->
    collectBody readBody >>= either throwE pure . decodeResponse meta

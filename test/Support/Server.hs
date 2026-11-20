module Support.Server
  ( withClient,
    withClientConfig,
    json,
    requestJson,
    assertEqual,
    assert,
    expectRight,
    within,
  )
where

import Claude.Client
import Data.Aeson (Value, eitherDecode, encode)
import Network.HTTP.Types (ResponseHeaders, Status)
import Network.Wai qualified as Wai
import Network.Wai.Handler.Warp qualified as Warp
import System.Timeout (timeout)

withClient :: Wai.Application -> (Client -> IO a) -> IO a
withClient = withClientConfig (defaultClientConfig "loopback-secret")

withClientConfig :: ClientConfig -> Wai.Application -> (Client -> IO a) -> IO a
withClientConfig config app run = Warp.testWithApplication (pure app) $ \port -> do
  client <- newClient config {endpoint = "http://127.0.0.1:" <> show port}
  expectRight client >>= within . run

json :: Status -> ResponseHeaders -> Value -> Wai.Response
json status headers = Wai.responseLBS status (("content-type", "application/json") : headers) . encode

requestJson :: Wai.Request -> IO Value
requestJson req = Wai.strictRequestBody req >>= expectRight . eitherDecode

assertEqual :: (Eq a, Show a) => String -> a -> a -> IO ()
assertEqual name expected actual =
  assert (name <> ": expected " <> show expected <> ", got " <> show actual) (expected == actual)

assert :: String -> Bool -> IO ()
assert name passed = if passed then pure () else fail name

expectRight :: (Show e) => Either e a -> IO a
expectRight = either (fail . show) pure

within :: IO a -> IO a
within action = timeout 10000000 action >>= maybe (fail "Fixture exceeded its deadline") pure

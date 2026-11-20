module Main (main) where

import Claude.Client
import Claude.Messages
import Data.ByteString.Char8 qualified as BS
import Data.List.NonEmpty (NonEmpty (..))
import System.Environment (getEnv)

main :: IO ()
main = do
  key <- BS.pack <$> getEnv "ANTHROPIC_API_KEY"
  client <- newClient (defaultClientConfig key) >>= either (fail . show) pure
  limit <- maybe (fail "Expected a positive output limit") pure (maxTokens 256)
  let prompt = Message User (InputText "Name three colors." :| [])
      request = MessageRequest (Conversation "claude-sonnet-4-6" (prompt :| []) Nothing defaultMessageFeatures) limit []
  createMessage client defaultRequestOptions request >>= \case
    Left err -> fail (show err)
    Right (Response _ result) -> print result

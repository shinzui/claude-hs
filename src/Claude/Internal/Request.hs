-- | Validate the envelope shared by typed requests and the streaming bridge.
module Claude.Internal.Request (validateMessages) where

import Claude.Internal.Http (Client, ClientError (..), clientApiVersion)
import Control.Monad (when)
import Data.Aeson (Object, Value (..), withObject, (.:))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser, parseEither)
import Data.Foldable (traverse_)
import Data.Text (Text)
import Data.Text qualified as Text
import Numeric.Natural (Natural)

validateMessages :: Client -> Bool -> Value -> Either ClientError Object
validateMessages client generates =
  either (Left . InvalidRequest . Text.pack) Right . parseEither (withObject "Messages request" validate)
  where
    current = clientApiVersion client == Just "2026-10-21"
    validate fields = do
      model <- fields .: "model"
      when (Text.null model) (fail "Messages require a model ID")
      when generates $ do
        limit <- fields .: "max_tokens"
        when ((limit :: Natural) == 0) (fail "Messages require positive max_tokens")
      history <- fields .: "messages" :: Parser [Value]
      when current $ do
        when (null history) (fail "Messages require a nonempty conversation")
        case filter (`KeyMap.member` fields) ["temperature", "top_p", "top_k"] of
          [] -> pure ()
          removed -> fail ("2026-10-21 removed sampling fields: " <> show removed)
        traverse_ (withObject "history message" validateTurn) history
      pure fields

validateTurn :: Object -> Parser ()
validateTurn turn = do
  role <- turn .: "role" :: Parser Text
  content <- turn .: "content" :: Parser Value
  case content of
    Array blocks -> traverse_ (withObject "history block" (validateBlock role)) blocks
    String _ -> pure ()
    _ -> fail "Message content must be a string or array"

validateBlock :: Text -> Object -> Parser ()
validateBlock role block = do
  tag <- block .: "type" :: Parser Text
  when (role == "assistant" && tag == "document") $
    fail "2026-10-21 requires documents in user messages"
  when (role == "user" && tag == "text") $
    case KeyMap.lookup "citations" block of
      Just (Array citations) | not (null citations) -> fail "2026-10-21 disallows citations in user messages"
      _ -> pure ()

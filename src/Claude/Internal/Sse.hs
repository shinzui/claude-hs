-- | Incremental, byte-oriented SSE framing.
module Claude.Internal.Sse (foldEvents) where

import Claude.Internal.Http (BodyReader, ClientError)
import Control.Monad.Trans.Except (ExceptT)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BSC
import Data.Char (isSpace)

-- | A handler may finish early with a value. A trailing incomplete event
-- never dispatches. The consumer decides what EOF means for the protocol.
foldEvents ::
  BodyReader ->
  (Maybe ByteString -> ByteString -> ExceptT ClientError IO (Maybe a)) ->
  ExceptT ClientError IO (Maybe a)
foldEvents readBody handle = feed initialFrame [] BS.empty
  where
    feed frame pieces chunk
      | BS.null chunk = do
          next <- readBody
          if BS.null next then pure Nothing else feed frame pieces next
      | otherwise = case BS.break (== 10) chunk of
          (prefix, rest)
            | BS.null rest -> feed frame (prefix : pieces) BS.empty
            | otherwise -> do
                let line = BS.concat (reverse (prefix : pieces))
                result <- acceptLine frame (BS.dropWhileEnd (== 13) line)
                case result of
                  Left done -> pure (Just done)
                  Right updated -> feed updated [] (BS.drop 1 rest)
    acceptLine frame line
      | BS.null line = case frame of
          Frame _ [] -> pure (Right initialFrame)
          Frame name parts ->
            let payload = BS.intercalate "\n" (reverse parts)
             in if BSC.all isSpace payload
                  then pure (Right initialFrame)
                  else do
                    result <- handle name payload
                    pure (maybe (Right initialFrame) Left result)
      | otherwise = pure (Right (addField frame line))

data Frame = Frame !(Maybe ByteString) ![ByteString]

initialFrame :: Frame
initialFrame = Frame Nothing []

addField :: Frame -> ByteString -> Frame
addField frame@(Frame name parts) line =
  case BS.break (== 58) line of
    ("event", suffix) -> Frame (Just (fieldValue suffix)) parts
    ("data", suffix) -> Frame name (fieldValue suffix : parts)
    _ -> frame
  where
    fieldValue suffix = case BS.drop 1 suffix of
      value | Just (32, rest) <- BS.uncons value -> rest
      value -> value

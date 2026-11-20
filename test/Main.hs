module Main (main) where

import FeaturesSpec qualified
import MessagesSpec qualified
import StreamingSpec qualified

main :: IO ()
main = MessagesSpec.run >> FeaturesSpec.run >> StreamingSpec.run

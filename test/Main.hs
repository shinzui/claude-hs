module Main (main) where

import BatchesSpec qualified
import FeaturesSpec qualified
import MessagesSpec qualified
import StreamingSpec qualified

main :: IO ()
main = MessagesSpec.run >> FeaturesSpec.run >> StreamingSpec.run >> BatchesSpec.run

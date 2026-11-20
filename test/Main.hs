module Main (main) where

import FeaturesSpec qualified
import MessagesSpec qualified

main :: IO ()
main = MessagesSpec.run >> FeaturesSpec.run

{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Cardano.Logging.Types.DocuGenerator
       (module Cardano.Logging.Types.DocuGenerator)
       where


import           Cardano.Logging.Types  (Namespace)

import           Data.Text              (Text, unpack)
import           Data.Text.Lazy.Builder (Builder)


-- Document all log messages by providing a list of DocMsgs for all constructors.
-- Because it is not enforced by the type system, it is very
-- important to provide a complete list, as the prototypes are used as well for configuration.
-- If you don't want to add an item for documentation enter an empty text.
newtype Documented a = Documented {undoc :: [DocMsg a]}
  deriving stock Show
  deriving newtype Semigroup

-- | Document a message by giving a prototype, its most special name in the namespace
-- and a comment in markdown format
data DocMsg a = DocMsg {
    dmNamespace :: Namespace a
  , dmMetricsMD :: [(Text, Text)]
  , dmMarkdown  :: Text
}

instance Show (DocMsg a) where
  show (DocMsg _ _ md) = unpack md


data DocuResult =
    DocuTracer Builder
  | DocuMetric Builder
  | DocuDatapoint Builder
  deriving Show

unpackDocu :: DocuResult -> Builder
unpackDocu (DocuTracer b)    = b
unpackDocu (DocuMetric b)    = b
unpackDocu (DocuDatapoint b) = b

resultIsTracer :: DocuResult -> Bool
resultIsTracer DocuTracer{} = True
resultIsTracer _            = False

resultIsMetric :: DocuResult -> Bool
resultIsMetric DocuMetric{} = True
resultIsMetric _            = False

resultIsDatapoint :: DocuResult -> Bool
resultIsDatapoint DocuDatapoint{} = True
resultIsDatapoint _               = False

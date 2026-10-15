-- | Text rendering helpers used pervasively by 'Hermod.Tracing.Types.LogFormatting'
--   instances.  Pure; no tracing semantics.
module Hermod.Tracing.Types.ShowT (
    showT
  , showTHex
  , showTReal
) where

import qualified Data.Text as T
import qualified Data.Text.Lazy as TL (toStrict)
import qualified Data.Text.Lazy.Builder as T (toLazyText)
import qualified Data.Text.Lazy.Builder.Int as T
import qualified Data.Text.Lazy.Builder.RealFloat as T (realFloat)


-- | Convenience function for a Show instance to be converted to text immediately
{-# INLINE showT #-}
showT :: Show a => a -> T.Text
showT = T.pack . show

{-# INLINE showTHex #-}
showTHex :: Integral a => a -> T.Text
showTHex = TL.toStrict . T.toLazyText . T.hexadecimal

{-# INLINE showTReal #-}
showTReal :: RealFloat a => a -> T.Text
showTReal = TL.toStrict . T.toLazyText . T.realFloat

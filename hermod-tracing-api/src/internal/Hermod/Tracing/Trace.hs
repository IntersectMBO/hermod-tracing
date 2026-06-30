{-# LANGUAGE ScopedTypeVariables #-}

-- | Per-message annotation and filtering combinators.
--
--   These operations attach labels (severity, privacy, detail level, namespace)
--   to messages, or filter messages based on those labels.  They wrap a
--   downstream 'Trace' and are composed left-to-right in the usual
--   contravariant style.
--
--   For structural combinators that shape the pipeline ('traceWith',
--   'contramapM', 'foldTraceM', 'routingTrace', …) see
--   "Hermod.Tracing.Trace.Combinators", which this module re-exports.
module Hermod.Tracing.Trace (
    module Hermod.Tracing.Trace.Combinators
  , filterTrace
  , filterTraceMaybe
) where

import           Hermod.Tracing.Trace.Combinators
import           Hermod.Tracing.Types

import qualified Control.Tracer as T


--- | Don't process further if the selector function returns 'False'.
filterTrace :: Monad m
  => ((LoggingContext, a) -> Bool)
  -> Trace m a
  -> Trace m a
filterTrace ff (Trace tr) = Trace $ T.squelchUnless
    (\case
      (_lc, Left _)  -> True
      (lc, Right a)  -> ff (lc, a))
      tr

--- | Keep 'Just' values; discard 'Nothing'.
filterTraceMaybe :: Monad m
  => Trace m a
  -> Trace m (Maybe a)
filterTraceMaybe (Trace tr) = Trace $
    T.squelchUnless
      (\case
        (_lc, Left _ctrl)     -> True
        (_lc, Right (Just _)) -> True
        (_lc, Right Nothing)  -> False)
      (T.contramap
          (\case
            ( lc, Right (Just a)) -> (lc, Right a)
            (_lc, Right Nothing)  -> error "filterTraceMaybe: impossible"
            ( lc, Left ctrl)      -> (lc, Left ctrl))
          tr)


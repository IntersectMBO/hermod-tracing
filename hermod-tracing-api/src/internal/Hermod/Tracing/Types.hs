{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs              #-}
{-# LANGUAGE BangPatterns #-}

-- | Core tracing machinery: the 'Trace' carrier, the 'TraceControl' GADT that
--   flows in-band through the pipeline, and the two key typeclasses
--   ('LogFormatting', 'MetaTrace') that message types implement.
--
--   This module re-exports 'Hermod.Tracing.Types.Annotations',
--   'Hermod.Tracing.Types.Config', and 'Hermod.Tracing.Types.Doc', so a
--   single @import Hermod.Tracing.Types@ gives access to the full type
--   hierarchy.
module Hermod.Tracing.Types (
    module Hermod.Tracing.Types.Annotations
  , module Hermod.Tracing.Types.Config
  , module Hermod.Tracing.Types.Doc
  , Trace(..)
  , LogFormatting(..)
  , MetaTrace(..)
  , TraceControl(..)
  , Folding(..)
  , unfold
) where

import           Hermod.Tracing.Types.Annotations
import           Hermod.Tracing.Types.Config
import           Hermod.Tracing.Types.Doc

import qualified Control.Tracer as T
import qualified Data.Aeson     as AE
import           Data.Text      (Text)


-- | The Trace carries the underlying 'T.Tracer' from the @contra-tracer@
--   package.  It adds a 'LoggingContext' and maybe a 'TraceControl' to every
--   message.
newtype Trace m a = Trace
    { unpackTrace :: T.Tracer m (LoggingContext, Either TraceControl a) }

-- | Contramap lifted to Trace.
instance Monad m => T.Contravariant (Trace m) where
    contramap f (Trace !tr) = Trace $! flip T.contramap tr $ \case
      (lc, Right a) -> (lc, Right (f a))
      (lc, Left tc) -> (lc, Left tc)

-- | @tr1 \<\> tr2@ will run @tr1@ and then @tr2@ with the same input.
instance Monad m => Semigroup (Trace m a) where
  Trace a1 <> Trace a2 = Trace (a1 <> a2)

instance Monad m => Monoid (Trace m a) where
    mappend = (<>)
    mempty  = Trace T.nullTracer


-- | When configuring a net of tracers, it should be run with 'TCConfig' on all
--   entry points first, and then with 'TCOptimize'.  When reconfiguring, run
--   'TCReset' followed by 'TCConfig' followed by 'TCOptimize'.
data TraceControl where
    TCReset    :: TraceControl
    TCConfig   :: TraceConfig     -> TraceControl
    TCOptimize :: ConfigReflection -> TraceControl
    TCDocument :: Int -> DocCollector -> TraceControl


-- | Every message type needs this to define how to represent itself.
class LogFormatting a where
  -- | Machine-readable representation with the possibility to render at varying
  --   verbosities.  This will result in JSON formatted log output.
  --   A @forMachine@ implementation is required for any instance definition.
  forMachine :: DetailLevel -> a -> AE.Object

  -- | Human-readable representation.
  --   The empty text indicates there is no specific human-readable formatting
  --   for that type — the default implementation.
  --
  --   If human-readable output is explicitly requested, the system will fall
  --   back to a JSON object conforming to the @forMachine@ definition,
  --   rendering it as @{\"data\": \<value\>}@.
  forHuman :: a -> Text
  forHuman _v = ""

  -- | Metrics representation.
  --   The default indicates that no metric is based on trace occurrences of
  --   that type.
  asMetrics :: a -> [Metric]
  asMetrics _v = []


class MetaTrace a where
  namespaceFor  :: a -> Namespace a

  severityFor   :: Namespace a -> Maybe a -> Maybe SeverityS
  privacyFor    :: Namespace a -> Maybe a -> Maybe Privacy
  privacyFor _  _ = Just Public
  detailsFor    :: Namespace a -> Maybe a -> Maybe DetailLevel
  detailsFor _  _ = Just DNormal

  documentFor   :: Namespace a -> Maybe Text
  metricsDocFor :: Namespace a -> [(Text, Text)]
  metricsDocFor _ = []
  allNamespaces :: [Namespace a]


-- | Wrapper used by 'Hermod.Tracing.Trace.foldTraceM' to carry the
--   accumulated value alongside the original message type.
newtype Folding a b = Folding b

unfold :: Folding a b -> b
unfold (Folding b) = b

instance LogFormatting b => LogFormatting (Folding a b) where
  forMachine v (Folding b) = forMachine v b
  forHuman (Folding b)     = forHuman b
  asMetrics (Folding b)    = asMetrics b

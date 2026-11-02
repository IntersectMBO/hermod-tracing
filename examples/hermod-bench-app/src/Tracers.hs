-- | Construction of the application's tracers, modelled on cardano-node's
--   @mkDispatchTracers@: one configured tracer per subsystem, and a record of
--   application-facing tracers that compose them the way the node does,
--   through the @contra-tracer@-compatible facade, whose 'Facade.Tracer' is
--   Hermod's 'Trace' and whose '<>' is 'Trace'\'s.
module Tracers
  ( AppTracers (..)
  , mkAppTracers
  , noTracers
  , countEmitted
  ) where

import           Cast

import           Hermod.Tracing
import qualified Hermod.Tracing.API.Tracer as Facade

import qualified Control.Tracer as T
import           Data.IORef
import           Data.Text (Text)


-- | The tracers the application's components trace to.
data AppTracers = AppTracers
  { naruto        :: Facade.Tracer IO Naruto
  , kakashi       :: Facade.Tracer IO Kakashi
  , sailorMoon    :: Facade.Tracer IO SailorMoon
  , sailorMercury :: Facade.Tracer IO SailorMercury
  , chihiro       :: Facade.Tracer IO Chihiro
  , noFace        :: Facade.Tracer IO NoFace
  , goku          :: Facade.Tracer IO Goku
  , vegeta        :: Facade.Tracer IO Vegeta
  , eren          :: Facade.Tracer IO Eren
  , levi          :: Facade.Tracer IO Levi
  }

-- | Builds and configures all tracers, and traces the tracer and
--   configuration information, as the node does at startup.  The 'IORef' is a
--   piece of application state that some tracers update, as the node's state
--   datapoint tracers do.
mkAppTracers
  :: Trace IO FormattedMessage
  -> Maybe (Trace IO FormattedMessage)
  -> TraceConfig
  -> IORef Int
  -> IO AppTracers
mkAppTracers trStdout mbTrEkg trConfig stateRef = do
    cr <- emptyConfigReflection
    let configured :: (LogFormatting a, MetaTrace a) => [Text] -> IO (Trace IO a)
        configured prefix = do
          !tr <- mkHermodTracer trStdout trForward mbTrEkg prefix
          configureTracers cr trConfig [tr]
          pure tr

    !narutoTr        <- configured ["Naruto"]
    !kakashiTr       <- configured ["Kakashi"]
    !sailorMoonTr    <- configured ["SailorMoon"]
    !sailorMercuryTr <- configured ["SailorMercury"]
    !chihiroTr       <- configured ["Chihiro"]
    !noFaceTr        <- configured ["NoFace"]
    !gokuTr          <- configured ["Goku"]
    !gokuFeatsTr     <- configured ["Goku", "Feats"]
    !vegetaTr        <- configured ["Vegeta"]
    !erenTr          <- configured ["Eren"]
    !leviTr          <- configured ["Levi"]
    !leviSquadTr     <- configured ["Squad", "Levi"]

    -- As the node's chainDBTracer: the main tracer without the events that a
    -- second tracer handles specially.
    let gokuTr' = filterTrace
                    (\case (_, PowerLevelOver9000) -> False
                           (_, SuperSaiyanTransformed {}) -> False
                           (_, _) -> True)
                    gokuTr
        gokuFeatsTr' = filterTrace
                    (\case (_, PowerLevelOver9000) -> True
                           (_, SuperSaiyanTransformed {}) -> True
                           (_, _) -> False)
                    gokuFeatsTr

    traceTracerInfo trStdout trForward cr
    traceEffectiveConfiguration trStdout trForward trConfig

    pure AppTracers
      { naruto        = Facade.mkTracer (traceWith narutoTr)
      , kakashi       = Facade.mkTracer (traceWith kakashiTr)
      , sailorMoon    = Facade.mkTracer (traceWith sailorMoonTr)
      , sailorMercury = Facade.mkTracer (traceWith sailorMercuryTr)
        -- as the node's startupTracer: the tracer and a state update
      , chihiro       = Facade.mkTracer (traceWith chihiroTr)
                        <> Facade.mkTracer (const (updateState stateRef))
      , noFace        = Facade.mkTracer (traceWith noFaceTr)
        -- as the node's chainDBTracer: two tracers and a state update
      , goku          = Facade.mkTracer (traceWith gokuTr')
                        <> Facade.mkTracer (traceWith gokuFeatsTr')
                        <> Facade.mkTracer (const (updateState stateRef))
      , vegeta        = Facade.mkTracer (traceWith vegetaTr)
      , eren          = Facade.mkTracer (traceWith erenTr)
                        <> Facade.mkTracer (const (updateState stateRef))
        -- as the node's nodeStateTracer: two configured tracers
      , levi          = Facade.mkTracer (traceWith leviTr)
                        <> Facade.mkTracer (traceWith leviSquadTr)
      }
  where
    -- Forwarding is downstream of what this application measures.
    trForward = mempty

-- | No tracing at all: the baseline of what the application costs without it.
noTracers :: AppTracers
noTracers = AppTracers
  { naruto = Facade.nullTracer, kakashi = Facade.nullTracer
  , sailorMoon = Facade.nullTracer, sailorMercury = Facade.nullTracer
  , chihiro = Facade.nullTracer, noFace = Facade.nullTracer
  , goku = Facade.nullTracer, vegeta = Facade.nullTracer
  , eren = Facade.nullTracer, levi = Facade.nullTracer
  }

updateState :: IORef Int -> IO ()
updateState ref = atomicModifyIORef' ref (\n -> (n + 1, ()))

-- | Counts the messages that reach the trace, i.e. the emitted ones when
--   wrapped around the stdout backend.
countEmitted :: IORef Int -> Trace IO FormattedMessage -> Trace IO FormattedMessage
countEmitted ref (Trace tr) = Trace $ T.arrow $ T.emit $ \case
    m@(_, Right _) -> do
      atomicModifyIORef' ref (\n -> (n + 1, ()))
      T.traceWith tr m
    m -> T.traceWith tr m

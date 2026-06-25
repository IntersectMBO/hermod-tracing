{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- HLINT ignore "Monad law, left identity" -}

module Hermod.Tracing.Tracer.Composed (
    mkHermodTracer
  , mkHermodTracer'
  , mkMetricsTracer
  , traceTracerInfo
  , traceConfigWarnings
  , traceEffectiveConfiguration
  ) where

import           Hermod.Tracing.Configuration
import           Hermod.Tracing.Formatter
import           Hermod.Tracing.Trace
import           Hermod.Tracing.TraceDispatcherMessage
import           Hermod.Tracing.Types

import           Control.Monad (when)
import qualified Control.Tracer as T
import           Data.IORef
import qualified Data.List as L
import           Data.Maybe (fromMaybe, isNothing)
import qualified Data.Set as Set
import           Data.Text hiding (map)


-- | Construct a tracer according to the requirements for cardano node.
-- The tracer gets a 'name', which is appended to its namespace.
-- The tracer has to be an instance of LogFormatting for the display of
-- messages and an instance of MetaTrace for meta information such as
-- severity, privacy, details and backends'.
-- The tracer gets the backends': 'trStdout', 'trForward' and 'mbTrEkg'
-- as arguments.
-- The returned tracer needs to be configured with a configuration
-- before it is used.
mkHermodTracer :: forall evt.
     ( LogFormatting evt
     , MetaTrace evt)
  => Trace IO FormattedMessage
  -> Trace IO FormattedMessage
  -> Maybe (Trace IO FormattedMessage)
  -> [Text]
  -> IO (Trace IO evt)
mkHermodTracer trStdout trForward mbTrEkg tracerPrefix =
    mkHermodTracer' trStdout trForward mbTrEkg tracerPrefix noHook
  where
    noHook :: Trace IO evt -> IO (Trace IO evt)
    noHook = pure

-- | Adds the possibility to add special tracers via the hook function
mkHermodTracer' :: forall evt evt1.
     ( LogFormatting evt1
     , MetaTrace evt1
     )
  => Trace IO FormattedMessage
  -> Trace IO FormattedMessage
  -> Maybe (Trace IO FormattedMessage)
  -> [Text]
  -> (Trace IO evt1 -> IO (Trace IO evt))
  -> IO (Trace IO evt)
mkHermodTracer' trStdout trForward mbTrEkg tracerPrefix hook = do

    !internalTr <-  backendsAndFormat
                      trStdout
                      trForward
                      Nothing
                      (Trace T.nullTracer)
                    >>= addContextAndFilter

    -- handle the messages
    !messageTrace <- withBackendsFromConfig (backendsAndFormat trStdout trForward)
                    >>= withLimitersFromConfig internalTr
                    >>= traceNamespaceErrors internalTr
                    >>= addContextAndFilter
                    >>= maybeSilent isSilentTracer tracerPrefix False
                    >>= hook

    -- handle the metrics
    !metricsTrace <- case mbTrEkg of
                      Nothing -> pure $ Trace T.nullTracer
                      Just ekgTrace ->
                        pure (metricsFormatter ekgTrace)
                        >>= maybeSilent hasNoMetrics tracerPrefix True
                        >>= hook

    pure (messageTrace <> metricsTrace)

  where
    {-# INLINE addContextAndFilter #-}
    addContextAndFilter :: MetaTrace a => Trace IO a -> IO (Trace IO a)
    addContextAndFilter tr = do
      tr'  <- withDetailsFromConfig
                $ withPrivacy
                  $ withDetails tr
      tr'' <- filterSeverityFromConfig tr'
      pure $ withNames tracerPrefix
             $ withSeverity tr''

    traceNamespaceErrors ::
         Trace IO TraceDispatcherMessage
      -> Trace IO evt1
      -> IO (Trace IO evt1)
    traceNamespaceErrors internalTr (Trace tr) = do
        pure $ Trace (T.arrow (T.emit
          (\case
            (lc, Right e) -> process lc (Right e)
            (lc, Left e) -> T.traceWith tr (lc, Left e))))
      where
        process :: LoggingContext -> Either TraceControl evt1 -> IO ()
        process lc cont = do
          when (isNothing (lcPrivacy lc)) $
                  traceWith
                    (appendPrefixNames ["Reflection"] internalTr)
                    (UnknownNamespace (lcNSPrefix lc) (lcNSInner lc) UKFPrivacy)
          when (isNothing (lcSeverity lc)) $
                  traceWith
                    (appendPrefixNames ["Reflection"] internalTr)
                    (UnknownNamespace (lcNSPrefix lc) (lcNSInner lc) UKFSeverity)
          when (isNothing (lcDetails lc)) $
                  traceWith
                    (appendPrefixNames ["Reflection"] internalTr)
                    (UnknownNamespace (lcNSPrefix lc) (lcNSInner lc) UKFDetails)
          T.traceWith tr (lc, cont)

backendsAndFormat ::
     LogFormatting a
  => Trace IO FormattedMessage
  -> Trace IO FormattedMessage
  -> Maybe [BackendConfig]
  -> Trace IO x
  -> IO (Trace IO a)
backendsAndFormat trStdout trForward mbBackends _ = do
    let mbForwardTrace  = if forwarder
                            then Just $ filterTraceByPrivacy (Just Public)
                                (forwardFormatter' trForward)
                            else Nothing
        mbStdoutTrace   | humColoured
                        = Just (humanFormatter' True trStdout)
                        | humUncoloured
                        = Just (humanFormatter' False trStdout)
                        | Stdout MachineFormat `L.elem` backends'
                        = Just (machineFormatter' trStdout)
                        | otherwise = Nothing
    case mbForwardTrace <> mbStdoutTrace of
      Nothing -> pure $ Trace T.nullTracer
      Just tr -> preFormatted (humColoured || humUncoloured || forwarder) tr
  where
    backends'     = fromMaybe
                    [Forwarder, Stdout MachineFormat]
                    mbBackends

    humColoured   = Stdout HumanFormatColoured   `L.elem` backends'
    humUncoloured = Stdout HumanFormatUncoloured `L.elem` backends'
    forwarder     = Forwarder `L.elem` backends'

traceConfigWarnings ::
     Trace IO FormattedMessage
  -> Trace IO FormattedMessage
  -> [Text]
  -> IO ()
traceConfigWarnings trStdout trForward errs = do
    internalTr <- backendsAndFormat
                      trStdout
                      trForward
                      Nothing
                      (Trace T.nullTracer)
    traceWith ((withInnerNames . appendPrefixNames ["Reflection"]. withSeverity)
                  internalTr)
              (TracerConsistencyWarnings errs)

traceEffectiveConfiguration ::
     Trace IO FormattedMessage
  -> Trace IO FormattedMessage
  -> TraceConfig
  -> IO ()
traceEffectiveConfiguration trStdout trForward trConfig = do
    internalTr <- backendsAndFormat
                      trStdout
                      trForward
                      Nothing
                      (Trace T.nullTracer)
    traceWith ((withInnerNames . appendPrefixNames ["Reflection"]. withSeverity)
                  internalTr)
              (TracerInfoConfig trConfig)

traceTracerInfo ::
     Trace IO FormattedMessage
  -> Trace IO FormattedMessage
  -> ConfigReflection
  -> IO ()
traceTracerInfo trStdout trForward cr = do
    internalTr <- backendsAndFormat
                      trStdout
                      trForward
                      Nothing
                      (Trace T.nullTracer)
    silentSet <- readIORef (crSilent cr)
    metricSet <- readIORef (crNoMetrics cr)
    allTracerSet <- readIORef (crAllTracers cr)
    let silentList  = map (intercalate (singleton '.')) (Set.toList silentSet)
    let metricsList = map (intercalate (singleton '.')) (Set.toList metricSet)
    let allTracersList = map (intercalate (singleton '.')) (Set.toList allTracerSet)
    traceWith ((withInnerNames . appendPrefixNames ["Reflection"]. withSeverity)
                  internalTr)
              (TracerInfo silentList metricsList allTracersList)
    writeIORef (crSilent cr) Set.empty
    writeIORef (crNoMetrics cr) Set.empty
    writeIORef (crAllTracers cr) Set.empty

-- A basic tracer just for metrics
mkMetricsTracer :: Maybe (Trace IO FormattedMessage) -> Trace IO FormattedMessage
mkMetricsTracer = fromMaybe (Trace T.nullTracer)

-- | A severity filter configured per namespace, as cardano-node's benchmark
--   configuration sets it up, for two of its tracers:
--
--   * Mempool: 8 namespaces, 'Debug' with three of them silenced.  Its
--     'AddedTx' and 'RejectedTx' carried 14% of all messages in a 16 h node
--     benchmark.
--   * ChainDB: 142 namespaces, 'Debug' with whole subtrees silenced, up to
--     seven names deep.
--
--   Each tracer is fed messages from a namespace with an own setting (a hit
--   in the exceptions) or with the common one (a miss); the uniform case,
--   the same tracer configured with a single severity, is the baseline.
module MixedConfig (
    mixedConfigBenchmarks
  ) where

import           Hermod.Tracing
import           Hermod.Tracing.Trace.Annotations (withNames, withSeverity)

import           Data.Map.Strict (fromList)
import           Data.Text (Text, splitOn)

import           Criterion.Main


mixedConfigBenchmarks :: IO Benchmark
mixedConfigBenchmarks = do
    mempoolUni   <- configured uniformDebug =<< stage ["Mempool"]
    mempool      <- configured benchConfig  =<< stage ["Mempool"]
    chainDBUni   <- configured uniformDebug =<< stage ["ChainDB"]
    chainDB      <- configured benchConfig  =<< stage ["ChainDB"]
    pure $ bgroup "mixedConfig"
      [ bench "1 Mempool, uniform config"     $ send mempoolUni addedTx
      , bench "2 Mempool, miss: AddedTx"      $ send mempool addedTx
      , bench "3 Mempool, hit: SyncNotNeeded" $ send mempool syncNotNeeded
      , bench "4 ChainDB, uniform config"     $ send chainDBUni starvation
      , bench "5 ChainDB, miss: ChainSelStarvationEvent"
                                              $ send chainDB starvation
      , bench "6 ChainDB, miss: AddBlockEvent.PipeliningEvent.SetTentativeHeader"
                                              $ send chainDB tentative
      , bench "7 ChainDB, hit: LedgerEvent.Forker.Read"
                                              $ send chainDB forkerRead
      , bench "8 ChainDB, hit: LedgerEvent.Flavor.V2.BackendTrace.LSM.LSMLookup"
                                              $ send chainDB lsmLookup
      ]
  where
    send :: Trace IO a -> a -> Benchmarkable
    send tr msg = whnfIO (traceWith tr msg)

    addedTx       = MempoolMsg ["AddedTx"]
    syncNotNeeded = MempoolMsg ["SyncNotNeeded"]
    starvation    = ChainDBMsg ["ChainSelStarvationEvent"]
    tentative     = ChainDBMsg ["AddBlockEvent", "PipeliningEvent", "SetTentativeHeader"]
    forkerRead    = ChainDBMsg ["LedgerEvent", "Forker", "Read"]
    lsmLookup     = ChainDBMsg ["LedgerEvent", "Flavor", "V2", "BackendTrace", "LSM", "LSMLookup"]

    -- The severity filter, with what 'mkHermodTracer' puts in front of it.
    stage :: MetaTrace a => [Text] -> IO (Trace IO a)
    stage prefix =
      withNames prefix . withSeverity <$> filterSeverityFromConfig (mkTrace (\_ -> pure ()))

    configured :: MetaTrace a => TraceConfig -> Trace IO a -> IO (Trace IO a)
    configured config tr = do
      cr <- emptyConfigReflection
      configureTracers cr config [tr]
      pure tr

-- | The severities of cardano-node's benchmark configuration for these
--   tracers.  The trailing dot of "ChainDB.LedgerEvent.Flavor.V1." is kept:
--   it makes a namespace that matches no message.
benchConfig :: TraceConfig
benchConfig = emptyTraceConfig {
  tcOptions = fromList $
    ([], [ConfSeverity (SeverityF (Just Notice))])
    : [ (splitOn "." ns, [ConfSeverity (SeverityF sev)])
      | (ns, sev) <-
          [ ("ChainDB",                                  Just Debug)
          , ("ChainDB.AddBlockEvent.AddBlockValidation", Nothing)
          , ("ChainDB.LedgerEvent.Flavor.V1.",           Nothing)
          , ("ChainDB.LedgerEvent.Flavor.V2",            Nothing)
          , ("ChainDB.LedgerEvent.Forker",               Nothing)
          , ("ChainDB.PerasCertDbEvent",                 Nothing)
          , ("ChainDB.ReplayBlock.LedgerReplay",         Just Notice)
          , ("Mempool",                                  Just Debug)
          , ("Mempool.AttemptAdd",                       Nothing)
          , ("Mempool.LedgerFound",                      Nothing)
          , ("Mempool.LedgerNotFound",                   Nothing)
          , ("Mempool.SyncNotNeeded",                    Nothing)
          , ("Mempool.Synced",                           Nothing)
          ]
      ]
  }

uniformDebug :: TraceConfig
uniformDebug = emptyTraceConfig {
  tcOptions = fromList [([], [ConfSeverity (SeverityF (Just Debug))])]
  }

newtype MempoolMsg = MempoolMsg [Text]

instance MetaTrace MempoolMsg where
  namespaceFor (MempoolMsg ns) = Namespace [] ns
  severityFor _ _   = Just Info
  documentFor _     = Nothing
  metricsDocFor _   = []
  allNamespaces     = map (Namespace [] . splitOn ".")
    [ "AddedTx"
    , "AttemptAdd"
    , "ManuallyRemovedTxs"
    , "RejectedTx"
    , "RemoveTxs"
    , "SyncNotNeeded"
    , "Synced"
    , "TipMovedBetweenSTMBlocks"
    ]

newtype ChainDBMsg = ChainDBMsg [Text]

-- | The namespaces of cardano-node's ChainDB tracer
--   (bench/trace-schemas/newNamespaces.txt), without the separate
--   ChainDB.ReplayBlock tracer.
instance MetaTrace ChainDBMsg where
  namespaceFor (ChainDBMsg ns) = Namespace [] ns
  severityFor _ _   = Just Info
  documentFor _     = Nothing
  metricsDocFor _   = []
  allNamespaces     = map (Namespace [] . splitOn ".")
    [ "AddBlockEvent.AddBlockValidation.InvalidBlock"
    , "AddBlockEvent.AddBlockValidation.UpdateLedgerDb"
    , "AddBlockEvent.AddBlockValidation.ValidCandidate"
    , "AddBlockEvent.AddedBlockToQueue"
    , "AddBlockEvent.AddedBlockToVolatileDB"
    , "AddBlockEvent.AddedReprocessLoEBlocksToQueue"
    , "AddBlockEvent.AddedToCurrentChain"
    , "AddBlockEvent.ChainSelectionLoEDebug"
    , "AddBlockEvent.ChangingSelection"
    , "AddBlockEvent.IgnoreBlockAlreadyInVolatileDB"
    , "AddBlockEvent.IgnoreBlockOlderThanK"
    , "AddBlockEvent.IgnoreInvalidBlock"
    , "AddBlockEvent.PipeliningEvent.OutdatedTentativeHeader"
    , "AddBlockEvent.PipeliningEvent.SetTentativeHeader"
    , "AddBlockEvent.PipeliningEvent.TrapTentativeHeader"
    , "AddBlockEvent.PoppedBlockFromQueue"
    , "AddBlockEvent.PoppedReprocessLoEBlocksFromQueue"
    , "AddBlockEvent.PoppingFromQueue"
    , "AddBlockEvent.StoreButDontChange"
    , "AddBlockEvent.SwitchedToAFork"
    , "AddBlockEvent.TryAddToCurrentChain"
    , "AddBlockEvent.TrySwitchToAFork"
    , "AddPerasCertEvent.AddedPerasCertToQueue"
    , "AddPerasCertEvent.ChainSelectionForBoostedBlock"
    , "AddPerasCertEvent.IgnorePerasCertTooOld"
    , "AddPerasCertEvent.PerasCertBoostsBlockNotYetReceived"
    , "AddPerasCertEvent.PerasCertBoostsCurrentChain"
    , "AddPerasCertEvent.PerasCertBoostsGenesis"
    , "AddPerasCertEvent.PoppedPerasCertFromQueue"
    , "ChainSelStarvationEvent"
    , "CopyToImmutableDBEvent.CopiedBlockToImmutableDB"
    , "CopyToImmutableDBEvent.NoBlocksToCopyToImmutableDB"
    , "FollowerEvent.FollowerNewImmIterator"
    , "FollowerEvent.FollowerNoLongerInMem"
    , "FollowerEvent.FollowerSwitchToMem"
    , "FollowerEvent.NewFollower"
    , "GCEvent.PerformedGC"
    , "GCEvent.ScheduledGC"
    , "ImmDbEvent.CacheEvent.CurrentChunkHit"
    , "ImmDbEvent.CacheEvent.PastChunkEvict"
    , "ImmDbEvent.CacheEvent.PastChunkExpired"
    , "ImmDbEvent.CacheEvent.PastChunkHit"
    , "ImmDbEvent.CacheEvent.PastChunkMiss"
    , "ImmDbEvent.ChunkFileDoesntFit"
    , "ImmDbEvent.ChunkValidation.InvalidChunkFile"
    , "ImmDbEvent.ChunkValidation.InvalidPrimaryIndex"
    , "ImmDbEvent.ChunkValidation.InvalidSecondaryIndex"
    , "ImmDbEvent.ChunkValidation.MissingChunkFile"
    , "ImmDbEvent.ChunkValidation.MissingPrimaryIndex"
    , "ImmDbEvent.ChunkValidation.MissingSecondaryIndex"
    , "ImmDbEvent.ChunkValidation.RewritePrimaryIndex"
    , "ImmDbEvent.ChunkValidation.RewriteSecondaryIndex"
    , "ImmDbEvent.ChunkValidation.StartedValidatingChunk"
    , "ImmDbEvent.ChunkValidation.ValidatedChunk"
    , "ImmDbEvent.DBAlreadyClosed"
    , "ImmDbEvent.DBClosed"
    , "ImmDbEvent.DeletingAfter"
    , "ImmDbEvent.Migrating"
    , "ImmDbEvent.NoValidLastLocation"
    , "ImmDbEvent.ValidatedLastLocation"
    , "InitChainSelEvent.InitialChainSelected"
    , "InitChainSelEvent.StartedInitChainSelection"
    , "InitChainSelEvent.Validation.InvalidBlock"
    , "InitChainSelEvent.Validation.UpdateLedgerDb"
    , "InitChainSelEvent.Validation.ValidCandidate"
    , "IteratorEvent.BlockGCedFromVolatileDB"
    , "IteratorEvent.BlockMissingFromVolatileDB"
    , "IteratorEvent.BlockWasCopiedToImmutableDB"
    , "IteratorEvent.StreamFromBoth"
    , "IteratorEvent.StreamFromImmutableDB"
    , "IteratorEvent.StreamFromVolatileDB"
    , "IteratorEvent.SwitchBackToVolatileDB"
    , "IteratorEvent.UnknownRangeRequested.ForkTooOld"
    , "IteratorEvent.UnknownRangeRequested.MissingBlock"
    , "LastShutdownUnclean"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.AlreadyClosed"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.Closed"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.Closing"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.Copied"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.Copying"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.CreatedValueHandle"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.CreatingValueHandle"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.InitialisedFromCopy"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.InitialisedFromValues"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.InitialisingFromCopy"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.InitialisingFromValues"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.Opened"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.Opening"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.ValueHandleTrace.AlreadyClosed"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.ValueHandleTrace.Closed"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.ValueHandleTrace.Closing"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.ValueHandleTrace.RangeRead"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.ValueHandleTrace.RangeReading"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.ValueHandleTrace.Read"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.ValueHandleTrace.Reading"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.ValueHandleTrace.Statted"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.ValueHandleTrace.Statting"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.Writing"
    , "LedgerEvent.Flavor.V1.LMDB.BackingStoreEvent.Written"
    , "LedgerEvent.Flavor.V1.LMDB.Initialise"
    , "LedgerEvent.Flavor.V2.BackendTrace.LSM.LSMLookup"
    , "LedgerEvent.Flavor.V2.BackendTrace.LSM.LSMOpenSession"
    , "LedgerEvent.Flavor.V2.BackendTrace.LSM.LSMSnap"
    , "LedgerEvent.Flavor.V2.BackendTrace.LSM.LSMTrace"
    , "LedgerEvent.Flavor.V2.BackendTrace.LSM.LSMUpdate"
    , "LedgerEvent.Flavor.V2.LedgerTablesHandleClose"
    , "LedgerEvent.Flavor.V2.LedgerTablesHandleCreate"
    , "LedgerEvent.Flavor.V2.LedgerTablesHandleCreateFirst"
    , "LedgerEvent.Flavor.V2.LedgerTablesHandleDuplicate"
    , "LedgerEvent.Flavor.V2.LedgerTablesHandlePush"
    , "LedgerEvent.Flavor.V2.LedgerTablesHandleRead"
    , "LedgerEvent.Forker.Close"
    , "LedgerEvent.Forker.Open"
    , "LedgerEvent.Forker.Push"
    , "LedgerEvent.Forker.RangeRead"
    , "LedgerEvent.Forker.Read"
    , "LedgerEvent.Forker.Statistics"
    , "LedgerEvent.Replay.ReplayProgress.ReplayedBlock"
    , "LedgerEvent.Replay.ReplayStart.ReplayFromGenesis"
    , "LedgerEvent.Replay.ReplayStart.ReplayFromSnapshot"
    , "LedgerEvent.Snapshot.DeletedSnapshot"
    , "LedgerEvent.Snapshot.InvalidSnapshot"
    , "LedgerEvent.Snapshot.TookSnapshot"
    , "OpenEvent.ClosedDB"
    , "OpenEvent.OpenedDB"
    , "OpenEvent.OpenedImmutableDB"
    , "OpenEvent.OpenedLgrDB"
    , "OpenEvent.OpenedVolatileDB"
    , "OpenEvent.StartedOpeningDB"
    , "OpenEvent.StartedOpeningImmutableDB"
    , "OpenEvent.StartedOpeningLgrDB"
    , "OpenEvent.StartedOpeningVolatileDB"
    , "PerasCertDbEvent.AddedPerasCert"
    , "PerasCertDbEvent.AddingPerasCert"
    , "PerasCertDbEvent.ClosedPerasCertDB"
    , "PerasCertDbEvent.IgnoredCertAlreadyInDB"
    , "PerasCertDbEvent.OpenedPerasCertDB"
    , "VolatileDbEvent.BlockAlreadyHere"
    , "VolatileDbEvent.DBAlreadyClosed"
    , "VolatileDbEvent.DBClosed"
    , "VolatileDbEvent.InvalidFileNames"
    , "VolatileDbEvent.Truncate"
    ]

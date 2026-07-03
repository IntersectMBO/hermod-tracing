module Hermod.Tracing.Test.Unit.ConfigFile (
    testConfigFileParsing
  , testConfigFileParsingResult
) where

import           Hermod.Tracing

import qualified Data.Map.Strict as Map


-- | Parse the example config shipped in @doc/config.json@ and return the
--   resulting 'TraceConfig'.
testConfigFileParsing :: IO TraceConfig
testConfigFileParsing = readConfiguration (FromFile "doc/config.json")

-- | The 'TraceConfig' that @doc/config.json@ is expected to parse to.
testConfigFileParsingResult :: TraceConfig
testConfigFileParsingResult = TraceConfig
  { tcOptions = Map.fromList
      [ ([], [ ConfSeverity (SeverityF (Just Notice))
             , ConfDetail DNormal
             , ConfBackend [Stdout MachineFormat]
             ])
      , (["Node"], [ ConfSeverity (SeverityF (Just Notice))
                   , ConfDetail DNormal
                   , ConfBackend [Stdout MachineFormat, EKGBackend, Forwarder]
                   ])
      , (["Node", "ChainDB"], [ConfSeverity (SeverityF (Just Info))])
      , (["Node", "AcceptPolicy"], [ConfSeverity (SeverityF (Just Info))])
      , (["Node", "DNSResolver"], [ConfSeverity (SeverityF (Just Info))])
      , (["Node", "DNSSubscription"], [ConfSeverity (SeverityF (Just Info))])
      , (["Node", "DiffusionInit"], [ConfSeverity (SeverityF (Just Info))])
      , (["Node", "ErrorPolicy"], [ConfSeverity (SeverityF (Just Info))])
      , (["Node", "Forge"], [ConfSeverity (SeverityF (Just Info))])
      , (["Node", "IpSubscription"], [ConfSeverity (SeverityF (Just Info))])
      , (["Node", "LocalErrorPolicy"], [ConfSeverity (SeverityF (Just Info))])
      , (["Node", "Mempool"], [ConfSeverity (SeverityF (Just Info))])
      , (["Node", "Resources"], [ConfSeverity (SeverityF (Just Info))])
      , (["Node", "ChainDB", "AddBlockEvent", "AddedBlockToQueue"], [ConfLimiter 2])
      , (["Node", "ChainDB", "AddBlockEvent", "AddedBlockToVolatileDB"], [ConfLimiter 2])
      , (["Node", "ChainDB", "CopyToImmutableDBEvent", "CopiedBlockToImmutableDB"], [ConfLimiter 2])
      , (["Node", "ChainDB", "AddBlockEvent", "AddBlockValidation", "ValidCandidate"], [ConfLimiter 2])
      , (["Node", "BlockFetchClient", "CompletedBlockFetch"], [ConfLimiter 2])
      ]
  , tcForwarder = Nothing
  , tcApplicationName = Nothing
  , tcMetricsPrefix = Nothing
  , tcPeriodicTracers = Map.fromList [("resources", 5000)]
  , tcPrometheusSimpleRun = Nothing
  }

module Hermod.Tracing.Test.Unit.ConfigFile (
    testConfigFileParsing
  , testConfigFileParsingResult
  , testLegacyConfigParsing
  , testLegacyConfigParsingResult
  , testLegacyConfigFileParsing
  , testLegacyConfigFileParsingResult
  , testBothLayoutsParsing
  , forwarderQueueSizeCases
) where

import           Hermod.Tracing

import qualified Data.Aeson as AE
import qualified Data.ByteString.Char8 as BS
import qualified Data.Map.Strict as Map
import           Data.Text (Text)

import           Paths_hermod_tracing_core (getDataFileName)


-- | Parse the example config shipped in @doc/config.json@ and return the
--   resulting 'TraceConfig'.
testConfigFileParsing :: IO TraceConfig
testConfigFileParsing = do
  configPath <- getDataFileName "doc/config.json"
  readConfiguration (FromFile configPath)

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

-- | Parse a configuration in trace-dispatcher's deprecated top-level layout,
--   shaped like the tracing part of cardano-node's shipped mainnet configuration.
testLegacyConfigParsing :: IO TraceConfig
testLegacyConfigParsing = readConfiguration $ FromStrictBytes $ BS.unlines
  [ "{ \"Protocol\": \"Cardano\""
  , ", \"UseTraceDispatcher\": true"
  , ", \"TraceOptionMetricsPrefix\": \"cardano.node.metrics.\""
  , ", \"TraceOptionNodeName\": \"node-1\""
  , ", \"TraceOptionResourceFrequency\": 1000"
  , ", \"TraceOptionLedgerMetricsFrequency\": 0"
  , ", \"TracePrometheusSimpleRun\": { \"connTimeout\": 30 }"
  , ", \"TraceOptionForwarder\": { \"connQueueSize\": 64, \"disconnQueueSize\": 128 }"
  , ", \"TraceOptions\":"
  , "    { \"\": { \"severity\": \"Notice\", \"detail\": \"DNormal\""
  , "          , \"backends\": [\"Stdout MachineFormat\", \"EKGBackend\", \"Forwarder\"] }"
  , "    , \"ChainDB\": { \"severity\": \"Info\" }"
  , "    }"
  , "}"
  ]

-- | What trace-dispatcher read from the configuration in 'testLegacyConfigParsing'.
testLegacyConfigParsingResult :: TraceConfig
testLegacyConfigParsingResult = TraceConfig
  { tcOptions = Map.fromList
      [ ([], [ ConfSeverity (SeverityF (Just Notice))
             , ConfDetail DNormal
             , ConfBackend [Stdout MachineFormat, EKGBackend, Forwarder]
             ])
      , (["ChainDB"], [ConfSeverity (SeverityF (Just Info))])
      ]
  , tcForwarder = Just defaultForwarder { tofQueueSize = 128 }
  , tcApplicationName = Just "node-1"
  , tcMetricsPrefix = Just "cardano.node.metrics."
  , tcPeriodicTracers = Map.fromList [("ledgerMetrics", 0), ("resources", 1000)]
  , tcPrometheusSimpleRun = Just prometheusSimpleNoOverrides { connTimeout = Just 30 }
  }

-- | Read @test/data/legacy-config.yaml@ the way an application reads its
--   configuration file: YAML, the "_root_" alias, an empty "HermodTracing" key
--   next to "TraceOptions", and a negative frequency.
testLegacyConfigFileParsing :: IO TraceConfig
testLegacyConfigFileParsing = do
  configPath <- getDataFileName "test/data/legacy-config.yaml"
  readConfiguration (FromFile configPath)

-- | What 'testLegacyConfigFileParsing' should yield.
testLegacyConfigFileParsingResult :: TraceConfig
testLegacyConfigFileParsingResult = TraceConfig
  { tcOptions = Map.fromList
      [ ([], [ ConfSeverity (SeverityF (Just Notice))
             , ConfDetail DNormal
             , ConfBackend [Stdout MachineFormat, Forwarder]
             ])
      , (["ChainDB"], [ConfSeverity (SeverityF (Just Info))])
      ]
  , tcForwarder = Just defaultForwarder { tofQueueSize = 128, tofMaxReconnectDelay = 30 }
  , tcApplicationName = Nothing
  , tcMetricsPrefix = Just "cardano.node.metrics."
  , tcPeriodicTracers = Map.fromList [("resources", 0)]
  , tcPrometheusSimpleRun = Nothing
  }

-- | A file giving both the deprecated and a current layout is read in the
--   deprecated one, as trace-dispatcher did; returns the application name and
--   the root severity found.
testBothLayoutsParsing :: IO (Maybe Text, [ConfigOption])
testBothLayoutsParsing = do
  tc <- readConfiguration $ FromStrictBytes $ BS.unlines
    [ "{ \"HermodTracing\":"
    , "    { \"Options\": { \"\": { \"severity\": \"Info\" } }"
    , "    , \"ApplicationName\": \"current\" }"
    , ", \"TraceOptions\": { \"\": { \"severity\": \"Debug\" } }"
    , ", \"TraceOptionNodeName\": \"deprecated\""
    , "}"
    ]
  pure ( tcApplicationName tc
       , [ o | o@ConfSeverity{} <- Map.findWithDefault [] [] (tcOptions tc) ] )

-- | Forwarder options and the queue size they yield: "queueSize" wins; else the
--   deprecated "connQueueSize" / "disconnQueueSize" give the larger of the two
--   (defaulting to 128 / 192), as in trace-dispatcher; else the default.
forwarderQueueSizeCases :: [(String, Either String Word, Word)]
forwarderQueueSizeCases =
  [ (src, tofQueueSize <$> AE.eitherDecodeStrict (BS.pack src), expected)
  | (src, expected) <-
      [ ("{}", 192)
      , ("{\"queueSize\": 50, \"connQueueSize\": 1000}", 50)
      , ("{\"connQueueSize\": 64, \"disconnQueueSize\": 128}", 128)
      , ("{\"connQueueSize\": 64}", 192)
      , ("{\"connQueueSize\": 1000}", 1000)
      , ("{\"disconnQueueSize\": 100}", 128)
      , ("{\"disconnQueueSize\": 1000}", 1000)
      ]
  ]

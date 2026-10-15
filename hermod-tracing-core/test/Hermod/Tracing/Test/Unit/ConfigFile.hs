module Hermod.Tracing.Test.Unit.ConfigFile (
    testConfigFileParsing
  , testConfigFileParsingResult
  , testNestedLegacyConfigParsing
  , testLegacyConfigParsingResult
  , testTopLevelLegacyConfigParsing
  , testNegativeFrequencyParsing
  , testLegacyConfigFileParsing
  , testLegacyConfigFileParsingResult
  , testReferencedLegacyFileDirectly
  , testBothLayoutsParsing
  , testNestedBothLayoutsParsing
  , testTopLevelCurrentNestedLegacyParsing
  , assertParseFailure
) where

import           Hermod.Tracing

import           Control.Exception (try)
import qualified Data.ByteString.Char8 as BS
import qualified Data.Map.Strict as Map
import           Data.Text (Text)
import           Data.Yaml (ParseException)
import           Test.Tasty.HUnit (Assertion, assertFailure)

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
  , tcPeriodicTracers = Map.fromList [("Resources", 5000)]
  , tcPrometheusSimpleRun = Nothing
  }

-- | The tracing part of cardano-node's shipped mainnet configuration, in
--   trace-dispatcher's deprecated layout: JSON object members, comma-separated.
legacyTracingMembers :: [BS.ByteString]
legacyTracingMembers =
  [ "  \"TraceOptionMetricsPrefix\": \"cardano.node.metrics.\""
  , ", \"TraceOptionNodeName\": \"node-1\""
  , ", \"TraceOptionResourceFrequency\": 1000"
  , ", \"TraceOptionLedgerMetricsFrequency\": 0"
  , ", \"TracePrometheusSimpleRun\": { \"connTimeout\": 30 }"
  , ", \"TraceOptionForwarder\": { \"queueSize\": 128 }"
  , ", \"TraceOptions\":"
  , "    { \"\": { \"severity\": \"Notice\", \"detail\": \"DNormal\""
  , "          , \"backends\": [\"Stdout MachineFormat\", \"EKGBackend\", \"Forwarder\"] }"
  , "    , \"ChainDB\": { \"severity\": \"Info\" }"
  , "    }"
  ]

-- | A configuration in trace-dispatcher's deprecated layout inside a
--   "HermodTracing" object.
testNestedLegacyConfigParsing :: IO TraceConfig
testNestedLegacyConfigParsing = readConfiguration $ FromStrictBytes $ BS.unlines $
  [ "{ \"Protocol\": \"Cardano\""
  , ", \"HermodTracing\":"
  , "  {"
  ] ++ legacyTracingMembers ++
  [ "  }"
  , "}"
  ]

-- | What 'testNestedLegacyConfigParsing' should yield.
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
  , tcPeriodicTracers = Map.fromList [("LedgerMetrics", 0), ("Resources", 1000)]
  , tcPrometheusSimpleRun = Just prometheusSimpleNoOverrides { connTimeout = Just 30 }
  }

-- | The deprecated layout at the top level of a configuration: not accepted.
testTopLevelLegacyConfigParsing :: IO TraceConfig
testTopLevelLegacyConfigParsing = readConfiguration $ FromStrictBytes $ BS.unlines $
  [ "{ \"Protocol\": \"Cardano\""
  , ","
  ] ++ legacyTracingMembers ++
  [ "}" ]

-- | A negative frequency in the deprecated layout: not accepted.
testNegativeFrequencyParsing :: IO TraceConfig
testNegativeFrequencyParsing = readConfiguration $ FromStrictBytes $ BS.unlines
  [ "{ \"HermodTracing\":"
  , "    { \"TraceOptions\": { \"\": { \"severity\": \"Notice\" } }"
  , "    , \"TraceOptionResourceFrequency\": -5 }"
  , "}"
  ]

-- | Read @test/data/legacy-node-config.yaml@, whose "HermodTracing" refers to
--   @legacy-config.yaml@, a YAML file in the deprecated layout using the
--   "_root_" alias.
testLegacyConfigFileParsing :: IO TraceConfig
testLegacyConfigFileParsing =
  readConfiguration (FromFile "test/data/legacy-node-config.yaml")

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
  , tcPeriodicTracers = Map.fromList [("Resources", 1000)]
  , tcPrometheusSimpleRun = Nothing
  }

-- | @test/data/legacy-config.yaml@ read as the application's configuration
--   file instead of through a "HermodTracing" reference: the deprecated layout
--   is then at the top level, and not accepted.
testReferencedLegacyFileDirectly :: IO TraceConfig
testReferencedLegacyFileDirectly = do
  -- a missing file is a parse error, too: make sure the fixture is there
  _ <- BS.readFile configPath
  readConfiguration (FromFile configPath)
  where
    configPath = "test/data/legacy-config.yaml"

-- | The deprecated layout at the top level and a current one in "HermodTracing":
--   the current one is read.
testBothLayoutsParsing :: IO (Maybe Text, [ConfigOption])
testBothLayoutsParsing = nameAndRootSeverity
  [ "{ \"HermodTracing\":"
  , "    { \"Options\": { \"\": { \"severity\": \"Info\" } }"
  , "    , \"ApplicationName\": \"current\" }"
  , ", \"TraceOptions\": { \"\": { \"severity\": \"Debug\" } }"
  , ", \"TraceOptionNodeName\": \"deprecated\""
  , "}"
  ]

-- | Both layouts inside "HermodTracing": the current one is read.
testNestedBothLayoutsParsing :: IO (Maybe Text, [ConfigOption])
testNestedBothLayoutsParsing = nameAndRootSeverity
  [ "{ \"HermodTracing\":"
  , "    { \"Options\": { \"\": { \"severity\": \"Info\" } }"
  , "    , \"ApplicationName\": \"current\""
  , "    , \"TraceOptions\": { \"\": { \"severity\": \"Debug\" } }"
  , "    , \"TraceOptionNodeName\": \"deprecated\" }"
  , "}"
  ]

-- | The current layout at the top level and the deprecated one in "HermodTracing":
--   the current one is read.
testTopLevelCurrentNestedLegacyParsing :: IO (Maybe Text, [ConfigOption])
testTopLevelCurrentNestedLegacyParsing = nameAndRootSeverity
  [ "{ \"Options\": { \"\": { \"severity\": \"Info\" } }"
  , ", \"ApplicationName\": \"current\""
  , ", \"HermodTracing\":"
  , "    { \"TraceOptions\": { \"\": { \"severity\": \"Debug\" } }"
  , "    , \"TraceOptionNodeName\": \"deprecated\" }"
  , "}"
  ]

-- | The application name and the root severity a configuration yields.
nameAndRootSeverity :: [BS.ByteString] -> IO (Maybe Text, [ConfigOption])
nameAndRootSeverity src = do
  tc <- readConfiguration $ FromStrictBytes $ BS.unlines src
  pure ( tcApplicationName tc
       , [ o | o@ConfSeverity{} <- Map.findWithDefault [] [] (tcOptions tc) ] )

-- | Reading the configuration fails with a parse error.
assertParseFailure :: IO TraceConfig -> Assertion
assertParseFailure act = do
  res <- try act :: IO (Either ParseException TraceConfig)
  case res of
    Left _   -> pure ()
    Right tc -> assertFailure $ "expected a parse error, got " ++ show tc

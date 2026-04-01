{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData          #-}

{-# OPTIONS_GHC -Wno-orphans #-}

module Cardano.Logging.ConfigurationParser
  ( mkConfiguration
  , mkConfigurationWithFallback
  , readConfiguration
  , readConfigurationWithFallback
  , readConfiguration'
  , readConfigurationWithFallback'
  , readConfigurationWithDefault
  , readConfigurationWithFallbackAndDefault
  , applyFallback
  , configToRepresentation
  ) where

import           Cardano.Logging.Types hiding (backends, detail, maxFrequency,
                                        severity)

import           Control.Applicative   ((<|>))
import           Control.Exception     (throwIO)
import qualified Data.Aeson            as AE
import           Data.List             as List (foldl')
import qualified Data.Map.Strict       as Map
import           Data.Maybe
import           Data.Text             as T (Text, intercalate, null, splitOn)
import           Data.Yaml             hiding (decodeFileEither)
import           Data.Yaml.Include     (decodeFileEither)
import           System.Directory      (doesFileExist)

-- -----------------------------------------------------------------------------
-- Configuration file

-- | The external representation of a configuration file
data ConfigRepresentation = ConfigRepresentation {
    traceOptions                      :: OptionsRepresentation
  , traceOptionForwarder              :: Maybe TraceOptionForwarder
  , traceOptionNodeName               :: Maybe Text
  , traceOptionMetricsPrefix          :: Maybe Text
  , traceOptionResourceFrequency      :: Maybe Int
  , traceOptionLedgerMetricsFrequency :: Maybe Int
  , tracePrometheusSimpleRun          :: Maybe PrometheusSimpleRun
  }
  deriving Show

instance AE.FromJSON ConfigRepresentation where
    parseJSON = withObject "HermodTracing" $ \obj ->
      parseAsLegacy obj <|> parseAsOuter obj <|> parseAsInner obj
      where
        -- the legacy format which current config files use
        parseAsLegacy obj =
          ConfigRepresentation
            <$> obj .:  "TraceOptions"
            <*> obj .:? "TraceOptionForwarder"
            <*> obj .:? "TraceOptionNodeName"
            <*> obj .:? "TraceOptionMetricsPrefix"
            <*> obj .:? "TraceOptionResourceFrequency"
            <*> obj .:? "TraceOptionLedgerMetricsFrequency"
            <*> obj .:? "TracePrometheusSimpleRun"

        -- configuration object has a top-level key -> object value "HermodTracing": {}
        parseAsOuter obj =
          obj .: "HermodTracing" >>= parseAsInner

        -- configuration object uses all HermodTracing key/values top-level
        parseAsInner obj =
          ConfigRepresentation
            <$> obj .:  "Options"
            <*> obj .:? "Forwarder"
            <*> obj .:? "ApplicationName"
            <*> obj .:? "MetricsPrefix"

            -- Those two will eventually be covered by a generalized configration for named periodic tracers.
            <*> pure Nothing
            <*> pure Nothing

            <*> obj .:? "PrometheusSimpleRun"


instance AE.ToJSON ConfigRepresentation where
  toJSON ConfigRepresentation{..} = object
    [ "Options"                  .= traceOptions
    , "Forwarder"                .= traceOptionForwarder
    , "ApplicationName"          .= traceOptionNodeName
    , "MetricsPrefix"            .= traceOptionMetricsPrefix
    , "PrometheusSimpleRun"      .= tracePrometheusSimpleRun
    ]

type OptionsRepresentation = Map.Map Text ConfigOptionRep

-- | In the external configuration representation for configuration files
-- all options for a namespace are part of a record
data ConfigOptionRep = ConfigOptionRep
    { severity     :: Maybe SeverityF
    , detail       :: Maybe DetailLevel
    , backends     :: Maybe [BackendConfig]
    , maxFrequency :: Maybe Double
    }
  deriving Show

instance AE.FromJSON ConfigOptionRep where
  parseJSON = withObject "ConfigOptionRep" $ \obj ->
    ConfigOptionRep
      <$> obj .:? "severity"
      <*> obj .:? "detail"
      <*> obj .:? "backends"
      <*> obj .:? "maxFrequency"

instance AE.ToJSON ConfigOptionRep where
  toJSON ConfigOptionRep{..} = object $
    catMaybes
      [ ("severity" .=)     <$> severity
      , ("detail" .=)       <$> detail
      , ("backends" .=)     <$> backends
      , ("maxFrequency" .=) <$> maxFrequency
      ]

instance AE.ToJSON TraceConfig where
  toJSON = toJSON . configToRepresentation


-- | Creates the minimal viable configuration by only setting fallback values in an empty TraceConfig.
--   Fallback options for the namespace root: Notice severity, normal detail, JSON stdout logging.
--   Notice severity was chosen as it will never filter out any actionable traces while creating minimal noise in the log.
mkConfiguration :: TraceConfig
mkConfiguration = mkConfigurationWithFallback Notice DNormal (Stdout MachineFormat)

-- | Creates the minimal viable configuration by only setting custom fallback values in an empty TraceConfig.
--   Fallback options for the namespace root: custom values.
mkConfigurationWithFallback :: SeverityS -> DetailLevel -> BackendConfig -> TraceConfig
mkConfigurationWithFallback fallbSev fallbDet fallbBack = applyFallback fallbSev fallbDet fallbBack emptyTraceConfig

-- | Read a configuration file and return the internal representation.
--   Fallback options for the namespace root: Notice severity, normal detail, JSON stdout logging.
readConfiguration :: FilePath -> IO TraceConfig
readConfiguration = readConfigurationWithFallback Notice DNormal (Stdout MachineFormat)

-- | Read a configuration file and return the internal representation.
--   Fallback options for the namespace root: custom values.
readConfigurationWithFallback :: SeverityS -> DetailLevel -> BackendConfig -> FilePath -> IO TraceConfig
readConfigurationWithFallback fallbSev fallbDet fallbBack = readConfigurationInt apFallback
  where
    apFallback = applyFallback fallbSev fallbDet fallbBack

-- | Read a configuration file and return the internal representation.
--   This will silently provide a minimal viable config via @mkConfiguration@ when the file is absent.
--   Fallback options for the namespace root: Notice severity, normal detail, JSON stdout logging.
readConfiguration' :: FilePath -> IO TraceConfig
readConfiguration' = readConfigurationWithFallback' Notice DNormal (Stdout MachineFormat)

-- | Read a configuration file and return the internal representation.
--   This will silently provide a minimal viable config via @mkConfigurationWithFallback@ when the file is absent.
--   Fallback options for the namespace root: custom values.
readConfigurationWithFallback' :: SeverityS -> DetailLevel -> BackendConfig -> FilePath -> IO TraceConfig
readConfigurationWithFallback' fallbSev fallbDet fallbBack fp = do
  exists <- doesFileExist fp
  if exists
    then readConfigurationInt (applyFallback fallbSev fallbDet fallbBack) fp
    else pure $ mkConfigurationWithFallback fallbSev fallbDet fallbBack

-- | Read a configuration file and return the internal representation.
--   TraceConfig fields not specified in the file will be taken from the provided @defaultConf@ (when given there).
--   Fallback options for the namespace root: Notice severity, normal detail, JSON stdout logging.
readConfigurationWithDefault :: FilePath -> TraceConfig -> IO TraceConfig
readConfigurationWithDefault = readConfigurationWithFallbackAndDefault Notice DNormal (Stdout MachineFormat)

-- | Read a configuration file and return the internal representation.
--   TraceConfig fields not specified in the file will be taken from the provided @defaultConf@ (when given there).
--   Fallback options for the namespace root: custom values.
readConfigurationWithFallbackAndDefault :: SeverityS -> DetailLevel -> BackendConfig -> FilePath -> TraceConfig -> IO TraceConfig
readConfigurationWithFallbackAndDefault fallbSev fallbDet fallbBack fp defaultConf = readConfigurationInt (apFallback . apDefault) fp
  where
    apFallback = applyFallback fallbSev fallbDet fallbBack
    apDefault  = mergeWithDefault defaultConf


-- In the config object, if the "HermodTracing" value is not an Object itself but a String,
-- it will be interpreted as a file path reference to the actual tracing config object.
newtype ExternalFile = ExternalFile FilePath

instance FromJSON ExternalFile where
  parseJSON = withObject "HermodTracing" $ \obj ->
    ExternalFile <$> obj .: "HermodTracing"

readConfigurationInt ::
     (TraceConfig -> TraceConfig)
  -> FilePath
  -> IO TraceConfig
readConfigurationInt modifyConf = go 4
  where
  go :: Int -> FilePath -> IO TraceConfig
  go redirects fp = do
    external :: Either ParseException ExternalFile <- decodeFileEither fp
    case external of
      Right (ExternalFile fp')
        | redirects > 0 -> go (redirects - 1) fp'
        | otherwise     -> error "hermod.readConfigurationInt: too many redirects"
      Left{} -> do
        confRep_ :: Either ParseException ConfigRepresentation <- decodeFileEither fp
        case confRep_ of
          Right confRep -> pure $! modifyConf $ representationToConfig $ unAliasRoot confRep
          Left e        -> throwIO e

-- right biased merge
mergeWithDefault :: TraceConfig -> TraceConfig -> TraceConfig
mergeWithDefault defaultConf fileConf =
  TraceConfig
    (if (not . Map.null) (tcOptions fileConf)
      then tcOptions fileConf
      else tcOptions defaultConf)
    (tcForwarder fileConf <|> tcForwarder defaultConf)
    (tcNodeName fileConf <|> tcNodeName defaultConf)
    (tcMetricsPrefix fileConf <|> tcMetricsPrefix defaultConf)
    (tcResourceFrequency fileConf <|> tcResourceFrequency defaultConf)
    (tcLedgerMetricsFrequency fileConf <|> tcLedgerMetricsFrequency defaultConf)
    (tcPrometheusSimpleRun fileConf <|> tcPrometheusSimpleRun defaultConf)

-- left biased merge
mergeOptionRepFields :: ConfigOptionRep -> ConfigOptionRep -> ConfigOptionRep
mergeOptionRepFields o1 o2 =
  ConfigOptionRep
    (severity o1     <|> severity o2)
    (detail o1       <|> detail o2)
    (backends o1     <|> backends o2)
    (maxFrequency o1 <|> maxFrequency o2)

-- | Applies the fallback values to the namespace root, or creates a namespace root from them if none is present.
--   If you do not use any of mkConfiguration* or readConfiguration* to create your TraceConfig, but do it manually,
--   it is highly recommended to call @applyFallback@ on that TraceConfig value as a last step before using it.
applyFallback :: SeverityS -> DetailLevel -> BackendConfig -> TraceConfig -> TraceConfig
applyFallback fallbSev fallbDet fallbBack tc@TraceConfig{tcOptions} =
  tc {tcOptions = Map.alter apply [] tcOptions}
  where
    apply Nothing     = Just $ representationToOptions fallback
    apply (Just root) = Just $ representationToOptions $
      optionsToRepresentation root `mergeOptionRepFields` fallback

    fallback = ConfigOptionRep
      { severity      = Just (SeverityF $ Just fallbSev)
      , detail        = Just fallbDet
      , backends      = Just [fallbBack]
      , maxFrequency  = Nothing
      }

-- The namespace root "" in the external representation can be aliased as "_root_".
-- Even though an empty JSON string is a valid key in an object, it does not
-- always play well with automations creating configs to enforce this.
-- This will remove aliasing from the representation; if both "_root_" and "" are defined in the config,
-- their options will be merged - however, this case should be avoided for clarity.
unAliasRoot :: ConfigRepresentation -> ConfigRepresentation
unAliasRoot confRep@ConfigRepresentation{traceOptions} =
  let
    alias = Map.lookup theAlias traceOptions
    root  = Map.lookup "" traceOptions
  in case alias `combine` root of
    Nothing   -> confRep
    Just opts ->
      let m' = Map.insert "" opts $ Map.delete theAlias traceOptions
      in  confRep {traceOptions = m'}
  where
    theAlias :: Text
    theAlias = "_root_"

    combine (Just a) (Just b) = Just $ a `mergeOptionRepFields` b
    combine a b               = a <|> b

-- | Convert from external to internal representation
representationToConfig :: ConfigRepresentation -> TraceConfig
representationToConfig = transform emptyTraceConfig
  where
    transform :: TraceConfig -> ConfigRepresentation -> TraceConfig
    transform TraceConfig {tcOptions=to'} cr =
      let to''  = List.foldl' (\ tci (nsp, opts') ->
                              let ns' = if T.null nsp then [] else splitOn "." nsp
                              in Map.insertWith
                                  (++)
                                  ns'
                                  (representationToOptions opts')
                                  tci)
                           to' (Map.toList (traceOptions cr))
      in TraceConfig
          to''
          (traceOptionForwarder cr)
          (traceOptionNodeName cr)
          (traceOptionMetricsPrefix cr)
          (traceOptionResourceFrequency cr)
          (traceOptionLedgerMetricsFrequency cr)
          (tracePrometheusSimpleRun cr)

-- | Convert options from external to internal representation
representationToOptions :: ConfigOptionRep -> [ConfigOption]
representationToOptions ConfigOptionRep{..} =
  catMaybes
    [ ConfSeverity  <$> severity
    , ConfDetail    <$> detail
    , ConfBackend   <$> backends
    , ConfLimiter   <$> maxFrequency
    ]

-- | Convert config from internal to external representation
configToRepresentation :: TraceConfig -> ConfigRepresentation
configToRepresentation traceConfig =
     ConfigRepresentation
        (toOptionRepresentation (tcOptions traceConfig))
        (tcForwarder traceConfig)
        (tcNodeName traceConfig)
        (tcMetricsPrefix traceConfig)
        (tcResourceFrequency traceConfig)
        (tcLedgerMetricsFrequency traceConfig)
        (tcPrometheusSimpleRun traceConfig)
  where
    toOptionRepresentation :: Map.Map [Text] [ConfigOption]
                              ->  Map.Map Text ConfigOptionRep
    toOptionRepresentation internalOptMap =
      List.foldl' conversion Map.empty (Map.toList internalOptMap)

    conversion :: Map.Map Text ConfigOptionRep
                -> ([Text],[ConfigOption])
                -> Map.Map Text ConfigOptionRep
    conversion accuMap (ns, options) =
      let nssingle   = intercalate "." ns
          optionRep = optionsToRepresentation options
      in  Map.insert nssingle optionRep accuMap

-- | Convert options from internal to external representation
optionsToRepresentation :: [ConfigOption] -> ConfigOptionRep
optionsToRepresentation opts =
  ConfigOptionRep
  { severity     = listToMaybe [d | ConfSeverity d <- opts]
  , detail       = listToMaybe [d | ConfDetail d <- opts]
  , backends     = listToMaybe [d | ConfBackend d <- opts]
  , maxFrequency = listToMaybe [d | ConfLimiter d <- opts]
  }

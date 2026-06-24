{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE RecordWildCards #-}

module Hermod.Tracing.Resources.Types
    ( Resources(..)
    , ResourceStats
    ) where


import           Cardano.Logging

import           Data.Aeson
import           Data.Text (pack)
import           Data.Word
import           GHC.Generics (Generic)

-- | A snapshot of resource usage for the current process, parameterised over
-- the numeric type @a@. The concrete alias 'ResourceStats' fixes @a ~ Word64@.
--
-- Fields that cannot be measured on the current platform are set to @0@.
data Resources a
  = Resources
      { rCentiCpu   :: !a
        -- ^ CPU time in centiseconds (1\/100 s) since process start,
        --   from @\/proc\/self\/stat@ on Linux or equivalent OS API.
      , rCentiGC    :: !a
        -- ^ CPU centiseconds spent in the GHC garbage collector (RTS stats).
      , rCentiMut   :: !a
        -- ^ CPU centiseconds spent in the mutator, i.e. application code (RTS stats).
      , rGcsMajor   :: !a
        -- ^ Number of major (full-heap) GC runs since process start (RTS stats).
      , rGcsMinor   :: !a
        -- ^ Number of minor GC runs since process start (RTS stats).
      , rAlloc      :: !a
        -- ^ Cumulative bytes allocated in the heap since process start (RTS stats).
      , rLive       :: !a
        -- ^ Live heap bytes immediately after the last GC run (RTS stats).
      , rHeap       :: !a
        -- ^ Committed heap bytes (total heap size reserved from the OS) (RTS stats).
      , rRSS        :: !a
        -- ^ Resident set size in bytes: physical memory currently mapped to
        --   the process (from the OS kernel).
      , rCentiBlkIO :: !a
        -- ^ Centiseconds spent waiting for block I/O (Linux @\/proc\/self\/stat@ only;
        --   @0@ on other platforms).
      , rNetRd      :: !a
        -- ^ IP packet bytes received since boot (Linux @\/proc\/self\/net\/netstat@,
        --   only when the @with-netstat@ flag is enabled; @0@ otherwise).
      , rNetWr      :: !a
        -- ^ IP packet bytes transmitted since boot (Linux @\/proc\/self\/net\/netstat@,
        --   only when the @with-netstat@ flag is enabled; @0@ otherwise).
      , rFsRd       :: !a
        -- ^ Filesystem bytes read by the process (from @\/proc\/self\/io@ on Linux
        --   or equivalent OS API).
      , rFsWr       :: !a
        -- ^ Filesystem bytes written by the process (from @\/proc\/self\/io@ on Linux
        --   or equivalent OS API).
      , rThreads    :: !a
        -- ^ Number of live GHC green threads (RTS stats).
      }
  deriving (Functor, Generic, Show)

-- | Concrete snapshot of resource usage with all fields as 'Word64' counts.
type ResourceStats = Resources Word64

instance Applicative Resources where
  pure a = Resources a a a a a a a a a a a a a a a
  f <*> x =
    Resources
    { rCentiCpu   = rCentiCpu   f (rCentiCpu   x)
    , rCentiGC    = rCentiGC    f (rCentiGC    x)
    , rCentiMut   = rCentiMut   f (rCentiMut   x)
    , rGcsMajor   = rGcsMajor   f (rGcsMajor   x)
    , rGcsMinor   = rGcsMinor   f (rGcsMinor   x)
    , rAlloc      = rAlloc      f (rAlloc      x)
    , rLive       = rLive       f (rLive       x)
    , rHeap       = rHeap       f (rHeap       x)
    , rRSS        = rRSS        f (rRSS        x)
    , rCentiBlkIO = rCentiBlkIO f (rCentiBlkIO x)
    , rNetRd = rNetRd f (rNetRd x)
    , rNetWr = rNetWr f (rNetWr x)
    , rFsRd  = rFsRd  f (rFsRd  x)
    , rFsWr  = rFsWr  f (rFsWr  x)
    , rThreads    = rThreads    f (rThreads    x)
    }

instance FromJSON a => FromJSON (Resources a) where
  parseJSON = genericParseJSON jsonEncodingOptions

instance ToJSON a => ToJSON (Resources a) where
  toJSON = genericToJSON jsonEncodingOptions
  toEncoding = genericToEncoding jsonEncodingOptions

jsonEncodingOptions :: Options
jsonEncodingOptions = defaultOptions
  { fieldLabelModifier     = drop 1
  , tagSingleConstructors  = True
  , sumEncoding =
    TaggedObject
    { tagFieldName = "kind"
    , contentsFieldName = "contents"
    }
  }

instance LogFormatting ResourceStats where
    forHuman Resources{..} = "Resources:"
                  <>  " Cpu Ticks "            <> (pack . show) rCentiCpu
                  <> ", GC centiseconds "      <> (pack . show) rCentiGC
                  <> ", Mutator centiseconds " <> (pack . show) rCentiMut
                  <> ", GCs major "            <> (pack . show) rGcsMajor
                  <> ", GCs minor "            <> (pack . show) rGcsMinor
                  <> ", Allocated bytes "      <> (pack . show) rAlloc
                  <>" , GC live bytes "        <> (pack . show) rLive
                  <> ", RTS heap "             <> (pack . show) rHeap
                  <> ", RSS "                  <> (pack . show) rRSS
                  <> ", Net bytes read "       <> (pack . show) rNetRd
                  <> " written "               <> (pack . show) rNetWr
                  <> ", FS bytes read "        <> (pack . show) rFsRd
                  <> " written "               <> (pack . show) rFsWr
                  <> ", Threads "              <> (pack . show) rThreads
                  <> "."

    forMachine _dtal rs = mconcat
      [ "kind"          .= String "ResourceStats"
      , "CentiCpu"      .= Number (fromIntegral $ rCentiCpu rs)
      , "CentiGC"       .= Number (fromIntegral $ rCentiGC rs)
      , "CentiMut"      .= Number (fromIntegral $ rCentiMut rs)
      , "GcsMajor"      .= Number (fromIntegral $ rGcsMajor rs)
      , "GcsMinor"      .= Number (fromIntegral $ rGcsMinor rs)
      , "Alloc"         .= Number (fromIntegral $ rAlloc rs)
      , "Live"          .= Number (fromIntegral $ rLive rs)
      , "Heap"          .= Number (fromIntegral $ rHeap rs)
      , "RSS"           .= Number (fromIntegral $ rRSS rs)
      , "CentiBlkIO"    .= Number (fromIntegral $ rCentiBlkIO rs)
      , "NetRd"    .= Number (fromIntegral $ rNetRd rs)
      , "NetWr"    .= Number (fromIntegral $ rNetWr rs)
      , "FsRd"     .= Number (fromIntegral $ rFsRd rs)
      , "FsWr"     .= Number (fromIntegral $ rFsWr rs)
      , "Threads"       .= Number (fromIntegral $ rThreads rs)
      ]

    asMetrics rs =
      [ IntM "Stat.cputicks"    (fromIntegral $ rCentiCpu rs)
      , IntM "RTS.gcticks"      (fromIntegral $ rCentiGC rs)
      , IntM "RTS.mutticks"     (fromIntegral $ rCentiMut rs)
      , IntM "RTS.gcMajorNum"   (fromIntegral $ rGcsMajor rs)
      , IntM "RTS.gcMinorNum"   (fromIntegral $ rGcsMinor rs)
      , IntM "RTS.alloc"        (fromIntegral $ rAlloc rs)
      , IntM "RTS.gcLiveBytes"            (fromIntegral $ rLive rs)
      , IntM "RTS.gcHeapBytes"         (fromIntegral $ rHeap rs)
      , IntM "Mem.resident"              (fromIntegral $ rRSS rs)
      , IntM "Stat.blkIOticks"  (fromIntegral $ rCentiBlkIO rs)
      , IntM "Stat.netRd"      (fromIntegral $ rNetRd rs)
      , IntM "Stat.netWr"      (fromIntegral $ rNetWr rs)
      , IntM "Stat.fsRd"       (fromIntegral $ rFsRd rs)
      , IntM "Stat.fsWr"       (fromIntegral $ rFsWr rs)
      , IntM "RTS.threads" (fromIntegral $ rThreads rs)
      ]

instance MetaTrace ResourceStats where
  namespaceFor Resources {} =
    Namespace [] ["Resources"]
  severityFor  (Namespace _ ["Resources"]) _ = Just Info
  severityFor _ns _ = Nothing
  documentFor  (Namespace _ ["Resources"]) = Just ""
  documentFor _ns = Nothing
  metricsDocFor  (Namespace _ ["Resources"]) =
    [("Stat.cputicks", "Kernel-reported CPU ticks (1/100th of a second), since process start")
    ,("RTS.gcticks", "RTS-reported CPU ticks spent on GC")
    ,("RTS.mutticks", "RTS-reported CPU ticks spent on mutator")
    ,("RTS.gcMajorNum", "Major GCs")
    ,("RTS.gcMinorNum", "Minor GCs")
    ,("RTS.alloc", "RTS-reported bytes allocated")
    ,("RTS.gcLiveBytes", "RTS-reported live bytes")
    ,("RTS.gcHeapBytes", "RTS-reported heap bytes")
    ,("Mem.resident", "Kernel-reported RSS (resident set size)")
    ,("Stat.netRd", "IP packet bytes read")
    ,("Stat.netWr", "IP packet bytes written")
    ,("Stat.fsRd", "FS bytes read")
    ,("Stat.fsWr", "FS bytes written")
    ,("RTS.threads","RTS green thread count")]
  metricsDocFor _ns = []
  allNamespaces = [ Namespace [] ["Resources"]]

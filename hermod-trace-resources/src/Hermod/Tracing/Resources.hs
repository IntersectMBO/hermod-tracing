{-# LANGUAGE CPP #-}

module Hermod.Tracing.Resources
    ( Resources(..)
    , ResourceStats
    , readResourceStats
    ) where


import           Hermod.Tracing.Resources.Types
#if defined(linux_HOST_OS)
import qualified Hermod.Tracing.Resources.Linux as Platform
#elif defined(mingw32_HOST_OS)
import qualified Hermod.Tracing.Resources.Windows as Platform
#elif defined(darwin_HOST_OS)
import qualified Hermod.Tracing.Resources.Darwin as Platform
#else
import qualified Hermod.Tracing.Resources.Dummy as Platform
#endif


readResourceStats :: IO (Maybe ResourceStats)
readResourceStats = Platform.readResourceStatsInternal

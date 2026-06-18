{-# LANGUAGE CPP #-}

-- | OS-level and RTS resource sampling for the Hermod tracing system.
--
-- This is the only public module of the package. Import it and call
-- 'readResourceStats' once per sampling interval to obtain a 'ResourceStats'
-- snapshot. The value carries 'LogFormatting' and 'MetaTrace' instances and
-- can be fed directly into any @Trace IO ResourceStats@.
--
-- Platform support:
--
-- * __Linux__ — CPU, GC, memory (RSS), block I/O, filesystem I/O, network (opt-in), threads.
-- * __macOS__ — CPU, GC, memory (RSS), network I/O, threads; disk I/O stubbed.
-- * __Windows__ — CPU, GC, memory (RSS), block I/O, threads.
-- * __Other__ — GHC RTS metrics (CPU, GC, threads) only; OS fields report 0.
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


-- | Sample resource usage of the current process.
--
-- Returns 'Nothing' only when the underlying OS interface is unavailable
-- (e.g. @\/proc@ not mounted). Under normal operating conditions this
-- always returns 'Just'.
--
-- The returned 'ResourceStats' is a @'Resources' 'Word64'@; fields that
-- cannot be measured on the current platform are set to @0@.
readResourceStats :: IO (Maybe ResourceStats)
readResourceStats = Platform.readResourceStatsInternal

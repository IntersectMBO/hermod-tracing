{-# LANGUAGE CPP #-}

import           Criterion.Main
import           Criterion.Types


#if defined(linux_HOST_OS)
import qualified Hermod.Tracing.Resources.Linux as Platform
#elif defined(mingw32_HOST_OS)
import qualified Hermod.Tracing.Resources.Windows as Platform
#elif defined(darwin_HOST_OS)
import qualified Hermod.Tracing.Resources.Darwin as Platform
#else
import qualified Hermod.Tracing.Resources.Dummy as Platform
#endif


main :: IO ()
main =
  defaultMainWith defaultConfig{ timeLimit = 15 }
    [ bench "create record ResourceStats" (whnfIO Platform.readResourceStatsInternal)
    ]

import           Criterion.Main
import           Criterion.Types

import           Hermod.Tracing.Resources (readResourceStats)


main :: IO ()
main =
  defaultMainWith defaultConfig{ timeLimit = 15 }
    [ bench "readResourceStats" (whnfIO readResourceStats)
    ]

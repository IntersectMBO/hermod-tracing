{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE RankNTypes        #-}

-- | Compile-only checks that the nullary synonym @type Tracer = Trace@
--   supports every shape found in ouroboros-network and ouroboros-consensus:
--   higher-kinded records instantiated at @Tracer m@, rank-2 polymorphic
--   tracers, an instance head on the synonym, and a tracer in 'STM'.
module Hermod.Tracing.API.Test.Shapes (
    Rec (..)
  , RecT
  , nullRec
  , withAll
  , Named (..)
  , stmTracer
) where

import           Hermod.Tracing.API.Tracer

import           GHC.Conc (STM)


-- | A higher-kinded record of tracers, as in consensus' @Tracers'@.
data Rec f = Rec { rInt :: f Int, rBool :: f Bool }

-- | The consensus idiom: @type Tracers m = Tracers' (Tracer m)@.
type RecT m = Rec (Tracer m)

nullRec :: Monad m => RecT m
nullRec = Rec nullTracer nullTracer

-- | The network-mux idiom: @tracersWith :: (forall x. Tracer m x) -> …@.
withAll :: (forall x. Tracer m x) -> RecT m
withAll tr = Rec tr tr

class Named a where
  name :: a -> String

-- | An instance head on the synonym, as consensus' NoThunks orphan.
instance Named (Tracer m ev) where
  name _ = "Tracer"

-- | A tracer in 'STM' type-checks (though it can never be configured).
stmTracer :: Tracer STM Int
stmTracer = nullTracer

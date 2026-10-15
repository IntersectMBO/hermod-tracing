-- | Bridges to APIs that still speak @contra-tracer@ directly.
--
--   Kept in a module of its own so that every remaining bridge in a code base
--   is greppable (@Hermod.Tracing.API.ContraTracer@) and can be burnt down.
--   No @contra-tracer@ build dependency is needed by importers as long as the
--   @Tracer@ type is not named in their own signatures.
module Hermod.Tracing.API.ContraTracer (
    toContraTracer
  , fromContraTracer
) where

import           Hermod.Tracing.Trace.Construct (fromContraTracer, toContraTracer)

-- | The narrow plumbing subset of "Hermod.Tracing.API": just the 'Trace' type
--   and the combinators needed to pass tracers around, adapt them and build
--   test doubles.  Nothing about namespaces, severities, metrics or
--   configuration is exported, so this module is safe to import unqualified
--   into library code without shadowing risk.
--
--   See "Hermod.Tracing.API" for the rules of using a 'Trace' in a library.
--   The @contra-tracer@-spelled equivalent is "Hermod.Tracing.API.Tracer".
module Hermod.Tracing.API.Trace (
    Trace
  , traceWith
  , mkTrace
  , nullTrace
  , natTrace
  , Contravariant (..)
  , (>$<)
  , contramapM
  , contramapMCond
  , filterTrace
  , filterTraceMaybe
  , routingTrace
  , debugTrace
  , stdoutTrace
) where

import           Hermod.Tracing.API

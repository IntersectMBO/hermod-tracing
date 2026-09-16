-- | The pure decision core of the "is hermod-recon actually emitting
--   machine-format JSON?" startup self-check.
--
--   The IO-facing policy (read the first several non-empty lines, bounded
--   by a short wall-clock timeout so a genuinely sparse @--mode online@
--   stream doesn't hang the check forever, or by end-of-stream in a short
--   finite/offline run) lives in "Main"; this module only tracks the
--   resulting state machine so it can be tested without any IO.
module Hermod.AlarmBridge.Startup
  ( StartupCheck (..)
  , initialStartupCheck
  , startupCheckLimit
  , StartupVerdict (..)
  , stepStartupCheck
  ) where

-- | @scPassed@ latches to 'True' forever once a single line parses as valid
--   hermod JSON -- after that point, a later isolated bad line is just
--   logged and skipped, never treated as a fresh startup failure.
--   @scFailures@ counts consecutive non-empty lines seen so far that failed
--   to parse, while @scPassed@ is still 'False'.
data StartupCheck = StartupCheck
  { scPassed   :: !Bool
  , scFailures :: !Int
  }
  deriving stock (Show, Eq)

initialStartupCheck :: StartupCheck
initialStartupCheck = StartupCheck { scPassed = False, scFailures = 0 }

-- | Number of non-empty parse failures (with no intervening success) that
--   condemns the stream as "not machine-format JSON".
startupCheckLimit :: Int
startupCheckLimit = 5

data StartupVerdict
  = StartupPending
    -- ^ Not enough evidence yet either way; keep reading.
  | StartupOk
    -- ^ At least one line parsed as valid hermod JSON.
  | StartupFailed
    -- ^ 'startupCheckLimit' consecutive non-empty lines all failed to parse.
  deriving stock (Show, Eq)

-- | Feed the parse outcome of one non-empty line (@True@ = it parsed as
--   valid hermod JSON) into the self-check state machine.
stepStartupCheck :: StartupCheck -> Bool -> (StartupCheck, StartupVerdict)
stepStartupCheck sc True = (sc { scPassed = True }, StartupOk)
stepStartupCheck sc False
  | scPassed sc = (sc, StartupOk)
  | otherwise   =
      let failures' = scFailures sc + 1
          sc'       = sc { scFailures = failures' }
      in if failures' >= startupCheckLimit
           then (sc', StartupFailed)
           else (sc', StartupPending)

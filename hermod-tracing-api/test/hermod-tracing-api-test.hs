-- | Semantics of the 1.1.0 construction/bridging primitives, checked in a
--   pure 'Writer' monad so that the test itself proves none of them needs
--   'MonadIO'.
module Main (main) where

import qualified Hermod.Tracing.API as API (contramapM, contramapMCond)
import           Hermod.Tracing.API.ContraTracer (fromContraTracer, toContraTracer)
import           Hermod.Tracing.API.Test.Shapes ()
import           Hermod.Tracing.API.Tracer
import           Hermod.Tracing.Types (Trace (..), TraceControl (..), emptyLoggingContext)

import qualified Control.Tracer as T
import qualified Control.Tracer.Arrow as TA

import           Control.Monad.Trans.Class (lift)
import           Control.Monad.Trans.Reader (ReaderT, runReaderT)
import           Control.Monad.Trans.Writer.Strict (Writer, runWriter, tell)
import           Test.Tasty
import           Test.Tasty.HUnit


type Log = Writer [String]

-- | A trace that records both messages and control messages.
observing :: Trace Log String
observing = Trace $ T.mkTracer $ \case
    (_, Right a) -> tell [a]
    (_, Left _)  -> tell ["ctrl"]

-- | Inject a control message at the root, as 'configureTracers' does.
sendControl :: Trace Log a -> Log ()
sendControl (Trace tr) = T.traceWith tr (emptyLoggingContext, Left TCReset)

logOf :: Log () -> [String]
logOf = snd . runWriter

isSquelching :: T.Tracer m a -> Bool
isSquelching tr = case T.runTracer tr of
    TA.Squelching _ -> True
    TA.Emitting _ _ -> False

main :: IO ()
main = defaultMain $ testGroup "hermod-tracing-api"
  [ testGroup "mkTracer"
      [ testCase "delivers messages" $
          logOf (traceWith (mkTracer (\a -> tell [a])) "x") @?= ["x"]
      , testCase "drops control messages (terminal sink)" $
          logOf (sendControl (mkTracer (\a -> tell [a :: String]))) @?= []
      ]
  , testGroup "nullTracer"
      [ testCase "is squelching" $
          (case nullTracer :: Tracer Log Int of Trace tr -> isSquelching tr) @?= True
      , testCase "does not evaluate a contramapped function" $
          logOf (traceWith (contramap (error "boom" :: () -> String) nullTracer) ()) @?= []
      ]
  , testGroup "control-preserving combinators"
      [ testCase "contramap forwards a control message exactly once" $
          logOf (sendControl (contramap (show :: Int -> String) observing)) @?= ["ctrl"]
      , testCase "contramap delivers the mapped message" $
          logOf (traceWith (show >$< observing) (1 :: Int)) @?= ["1"]
      , testCase "natTracer forwards messages and controls" $
          let lifted :: Tracer (ReaderT () Log) String
              lifted = natTracer lift observing
              run act = logOf (runReaderT act ())
          in (run (traceWith lifted "m"), run (sendControl' lifted)) @?= (["m"], ["ctrl"])
      , testCase "contramapM (function first) runs its effect and delivers" $
          logOf (traceWith (contramapM (\a -> tell ["effect"] >> pure (a ++ "!")) observing) "m")
            @?= ["effect", "m!"]
      , testCase "contramapM forwards a control without running the effect" $
          logOf (sendControl (contramapM (\a -> tell ["effect"] >> pure (a :: String)) observing))
            @?= ["ctrl"]
      , testCase "contramapM does not run its effect over nullTracer" $
          logOf (traceWith (contramapM (\a -> tell ["effect"] >> pure (a :: String)) nullTracer) "m")
            @?= []
      , testCase "API.contramapM (trace first) has the same semantics" $
          ( logOf (traceWith (API.contramapM observing (\a -> tell ["effect"] >> pure (a ++ "!"))) "m")
          , logOf (traceWith (API.contramapM nullTracer (\a -> tell ["effect"] >> pure (a :: String))) "m")
          , logOf (sendControl (API.contramapM observing (\a -> tell ["effect"] >> pure (a :: String))))
          ) @?= (["effect", "m!"], [], ["ctrl"])
      , testCase "API.contramapMCond keeps Just, drops Nothing, forwards controls" $
          let keepUnless :: String -> String -> Log (Maybe String)
              keepUnless x a = tell ["effect"] >> pure (if a == x then Nothing else Just a)
          in ( logOf (traceWith (API.contramapMCond observing (keepUnless "drop")) "keep")
             , logOf (traceWith (API.contramapMCond observing (keepUnless "drop")) "drop")
             , logOf (traceWith (API.contramapMCond nullTracer (keepUnless "drop")) "keep")
             , logOf (sendControl (API.contramapMCond observing (keepUnless "drop")))
             ) @?= (["effect", "keep"], ["effect"], [], ["ctrl"])
      , testCase "<> broadcasts a control message to both branches" $
          logOf (sendControl (observing <> observing)) @?= ["ctrl", "ctrl"]
      ]
  , testGroup "contra-tracer bridges"
      [ testCase "toContraTracer delivers into the pipeline" $
          logOf (T.traceWith (toContraTracer observing) "x") @?= ["x"]
      , testCase "toContraTracer of nullTracer is squelching" $
          isSquelching (toContraTracer (nullTracer :: Tracer Log Int)) @?= True
      , testCase "fromContraTracer delivers messages" $
          logOf (traceWith (fromContraTracer (T.mkTracer (\a -> tell [a]))) "x") @?= ["x"]
      , testCase "fromContraTracer drops control messages" $
          logOf (sendControl (fromContraTracer (T.mkTracer (\a -> tell [a :: String])))) @?= []
      , testCase "round trip keeps squelching" $
          isSquelching (toContraTracer (fromContraTracer (T.nullTracer :: T.Tracer Log Int))) @?= True
      ]
  ]
  where
    sendControl' :: Tracer (ReaderT () Log) a -> ReaderT () Log ()
    sendControl' (Trace tr) = T.traceWith tr (emptyLoggingContext, Left TCReset)

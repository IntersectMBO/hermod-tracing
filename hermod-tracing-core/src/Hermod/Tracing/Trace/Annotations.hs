{-# LANGUAGE ScopedTypeVariables #-}

module Hermod.Tracing.Trace.Annotations (
    filterTraceBySeverity
  , filterTraceByPrivacy

  , setSeverity
  , withSeverity
  , privately
  , setPrivacy
  , withPrivacy
  , allPublic
  , allConfidential
  , setDetails
  , withDetails

  , withNames
  , appendPrefixName
  , appendPrefixNames
  , appendInnerName
  , appendInnerNames
  , withInnerNames
  , withLoggingContext
) where

import           Hermod.Tracing.Trace (filterTrace)
import           Hermod.Tracing.Types

import qualified Control.Tracer as T
import           Data.Maybe     (isJust)
import           Data.Text      (Text)


--- | Only process messages with severity ≥ the given minimum.
filterTraceBySeverity :: Monad m
  => Maybe SeverityF
  -> Trace m a
  -> Trace m a
filterTraceBySeverity (Just minSeverity) =
    filterTrace
      (\(lc, _) -> case lcSeverity lc of
                      Just s  -> case minSeverity of
                                    SeverityF (Just fs) -> s >= fs
                                    SeverityF Nothing   -> False
                      Nothing -> True)
filterTraceBySeverity Nothing = id

--- | Only process messages whose privacy level ≥ the given minimum.
filterTraceByPrivacy :: Monad m
  => Maybe Privacy
  -> Trace m a
  -> Trace m a
filterTraceByPrivacy (Just minPrivacy) = filterTrace $
    \(lc, _cont) ->
        case lcPrivacy lc of
          Just s  -> fromEnum s >= fromEnum minPrivacy
          Nothing -> True
filterTraceByPrivacy Nothing = id


-- | Set a fixed 'SeverityS' on every message (no-op if already set).
setSeverity :: Monad m => SeverityS -> Trace m a -> Trace m a
setSeverity s (Trace tr) = Trace $
    T.contramap
      (\(lc, cont) ->
          if isJust (lcSeverity lc)
            then (lc, cont)
            else (lc {lcSeverity = Just s}, cont))
      tr

-- | Set severity from the 'MetaTrace' instance for each message.
{-# INLINE withSeverity #-}
withSeverity :: forall m a. (Monad m, MetaTrace a) => Trace m a -> Trace m a
withSeverity (Trace tr) = Trace $
    T.contramap
      (\case
        (lc, Right e)             -> process lc (Right e)
        (lc, Left c@(TCConfig _)) -> process lc (Left c)
        (lc, Left d@(TCDocument _ _)) -> process lc (Left d)
        (lc, Left e)              -> (lc, Left e))
      tr
  where
    process lc cont@(Right v) =
      if isJust (lcSeverity lc)
        then (lc, cont)
        else (lc {lcSeverity = severityFor (Namespace [] (lcNSInner lc) :: Namespace a) (Just v)}, cont)
    process lc cont@(Left _) =
      if isJust (lcSeverity lc)
        then (lc, cont)
        else (lc {lcSeverity = severityFor (Namespace [] (lcNSInner lc) :: Namespace a) Nothing}, cont)


allPublic :: a -> Privacy
allPublic _ = Public

allConfidential :: a -> Privacy
allConfidential _ = Confidential

-- | Set 'Confidential' privacy on every message.
privately :: Monad m => Trace m a -> Trace m a
privately = setPrivacy Confidential

-- | Set a fixed 'Privacy' on every message (no-op if already set).
setPrivacy :: Monad m => Privacy -> Trace m a -> Trace m a
setPrivacy p (Trace tr) = Trace $
    T.contramap
      (\(lc, cont) ->
          if isJust (lcPrivacy lc)
            then (lc, cont)
            else (lc {lcPrivacy = Just p}, cont))
      tr

-- | Set privacy from the 'MetaTrace' instance for each message.
withPrivacy :: forall m a. (Monad m, MetaTrace a) => Trace m a -> Trace m a
withPrivacy (Trace tr) = Trace $
    T.contramap
      (\case
        (lc, Right e)             -> process lc (Right e)
        (lc, Left c@(TCConfig _)) -> process lc (Left c)
        (lc, Left d@(TCDocument _ _)) -> process lc (Left d)
        (lc, Left e)              -> (lc, Left e))
      tr
  where
    process lc cont@(Right v) =
      if isJust (lcPrivacy lc)
        then (lc, cont)
        else (lc {lcPrivacy = privacyFor (Namespace [] (lcNSInner lc) :: Namespace a) (Just v)}, cont)
    process lc cont@(Left _) =
      if isJust (lcPrivacy lc)
        then (lc, cont)
        else (lc {lcPrivacy = privacyFor (Namespace [] (lcNSInner lc) :: Namespace a) Nothing}, cont)


-- | Set a fixed 'DetailLevel' on every message (no-op if already set).
setDetails :: Monad m => DetailLevel -> Trace m a -> Trace m a
setDetails p (Trace tr) = Trace $
    T.contramap
      (\(lc, cont) ->
          if isJust (lcDetails lc)
            then (lc, cont)
            else (lc {lcDetails = Just p}, cont))
      tr

-- | Set detail level from the 'MetaTrace' instance for each message.
withDetails :: forall m a. (Monad m, MetaTrace a) => Trace m a -> Trace m a
withDetails (Trace tr) = Trace $
    T.contramap
      (\case
        (lc, Right e)             -> process lc (Right e)
        (lc, Left c@(TCConfig _)) -> process lc (Left c)
        (lc, Left d@(TCDocument _ _)) -> process lc (Left d)
        (lc, Left e)              -> (lc, Left e))
      tr
  where
    process lc cont@(Right v) =
      if isJust (lcDetails lc)
        then (lc, cont)
        else (lc {lcDetails = detailsFor (Namespace [] (lcNSInner lc) :: Namespace a) (Just v)}, cont)
    process lc cont@(Left _) =
      if isJust (lcDetails lc)
        then (lc, cont)
        else (lc {lcDetails = detailsFor (Namespace [] (lcNSInner lc) :: Namespace a) Nothing}, cont)


-- | Set prefix and inner namespace from the 'MetaTrace' instance for each
--   message, prepending the given prefix names.
{-# INLINE withNames #-}
withNames :: forall m a. (Monad m, MetaTrace a) => [Text] -> Trace m a -> Trace m a
withNames names (Trace tr) = Trace $
    T.contramap
      (\case
        (lc, Right a) -> (lc {lcNSPrefix = names,
                              lcNSInner  = nsInner (namespaceFor a)}, Right a)
        (lc, Left c)  -> (lc {lcNSPrefix = names}, Left c))
      tr

-- | Set inner namespace from the 'MetaTrace' instance for each message.
{-# INLINE withInnerNames #-}
withInnerNames :: forall m a. (Monad m, MetaTrace a) => Trace m a -> Trace m a
withInnerNames (Trace tr) = Trace $
    T.contramap
      (\case
        (lc, Right a) -> (lc {lcNSInner = nsInner (namespaceFor a)}, Right a)
        (lc, Left c)  -> (lc, Left c))
      tr

-- | Prepend a single name to the namespace prefix.
appendPrefixName :: Monad m => Text -> Trace m a -> Trace m a
appendPrefixName name (Trace tr) = Trace $
    T.contramap
      (\(lc, cont) -> (lc {lcNSPrefix = name : lcNSPrefix lc}, cont))
      tr

appendInnerName :: Monad m => Text -> Trace m a -> Trace m a
appendInnerName name (Trace tr) = Trace $
    T.contramap
      (\(lc, cont) -> (lc {lcNSInner = name : lcNSInner lc}, cont))
      tr

-- | Prepend several names to the namespace prefix.
{-# INLINE appendPrefixNames #-}
appendPrefixNames :: Monad m => [Text] -> Trace m a -> Trace m a
appendPrefixNames names (Trace tr) = Trace $
    T.contramap
      (\(lc, cont) -> (lc {lcNSPrefix = names ++ lcNSPrefix lc}, cont))
      tr

appendInnerNames :: Monad m => [Text] -> Trace m a -> Trace m a
appendInnerNames names (Trace tr) = Trace $
    T.contramap
      (\(lc, cont) -> (lc {lcNSInner = names ++ lcNSInner lc}, cont))
      tr

-- | Replace the logging context for all messages passing through this trace.
withLoggingContext :: Monad m => LoggingContext -> Trace m a -> Trace m a
withLoggingContext lc (Trace tr) = Trace $
    T.contramap (\(_lc, cont) -> (lc, cont)) tr

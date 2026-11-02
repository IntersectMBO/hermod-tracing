-- | The traced events of the benchmark application: one type per character,
--   each the event vocabulary of a subsystem, as an application defines one
--   type per component.
--
--   Fields are lazy on purpose: as with a lazily constructed trace in an
--   application, a filtered message's fields are never evaluated.
--
--   Each character also lists its events with a weight and a constructor from
--   a random word ('Events'), from which the workers draw their messages.
module Cast
  ( Naruto (..)
  , Kakashi (..)
  , SailorMoon (..)
  , SailorMercury (..)
  , Chihiro (..)
  , NoFace (..)
  , Goku (..)
  , Vegeta (..)
  , Eren (..)
  , Levi (..)
  , Events
  , narutoEvents
  , kakashiEvents
  , sailorMoonEvents
  , sailorMercuryEvents
  , chihiroEvents
  , noFaceEvents
  , gokuEvents
  , vegetaEvents
  , erenEvents
  , leviEvents
  ) where

import           Hermod.Tracing

import           Data.Aeson (Object, Value (String), (.=))
import           Data.Text (Text)
import           Data.Word (Word64)


-- | Events with a relative weight and a constructor from a random word.
type Events a = [(Int, Word64 -> a)]

pick :: [Text] -> Word64 -> Text
pick xs w = xs !! fromIntegral (w `mod` fromIntegral (length xs))

int :: Word64 -> Word64 -> Int
int range w = fromIntegral (w `mod` range)

double :: Word64 -> Word64 -> Double
double range w = fromIntegral (w `mod` (range * 100)) / 100

kind :: Text -> Object
kind k = "kind" .= String k

-------------------------------------------------------------------------------
-- Naruto

data Naruto
  = ShadowCloneSpawned Int
  | ShadowCloneDispelled Int
  | RasenganCharging Double
  | RasenganHit Text Int
  | RamenOrdered Int
  | RamenIchirakuClosed
  | NineTailsChakraLeaking Double
  | HokageDreamDeclared

instance LogFormatting Naruto where
  forMachine _ = \case
    ShadowCloneSpawned n     -> kind "ShadowCloneSpawned" <> "count" .= n
    ShadowCloneDispelled n   -> kind "ShadowCloneDispelled" <> "count" .= n
    RasenganCharging c       -> kind "RasenganCharging" <> "chakra" .= c
    RasenganHit t d          -> kind "RasenganHit" <> "target" .= t <> "damage" .= d
    RamenOrdered b           -> kind "RamenOrdered" <> "bowls" .= b
    RamenIchirakuClosed      -> kind "RamenIchirakuClosed"
    NineTailsChakraLeaking l -> kind "NineTailsChakraLeaking" <> "level" .= l
    HokageDreamDeclared      -> kind "HokageDreamDeclared"
  asMetrics = \case
    ShadowCloneSpawned n -> [IntM "Naruto.shadowClones" (fromIntegral n)]
    RamenOrdered b       -> [CounterM "Naruto.ramen.bowls" (CounterAdd (fromIntegral b))]
    _                    -> []

instance MetaTrace Naruto where
  namespaceFor = Namespace [] . \case
    ShadowCloneSpawned {}     -> ["ShadowClone", "Spawned"]
    ShadowCloneDispelled {}   -> ["ShadowClone", "Dispelled"]
    RasenganCharging {}       -> ["Rasengan", "Charging"]
    RasenganHit {}            -> ["Rasengan", "Hit"]
    RamenOrdered {}           -> ["Ramen", "Ordered"]
    RamenIchirakuClosed       -> ["Ramen", "Ichiraku", "Closed"]
    NineTailsChakraLeaking {} -> ["NineTails", "Chakra", "Leaking"]
    HokageDreamDeclared       -> ["Hokage", "Dream", "Declared"]
  severityFor (Namespace _ ns) _ = case ns of
    ["ShadowClone", "Spawned"]        -> Just Debug
    ["ShadowClone", "Dispelled"]      -> Just Debug
    ["Rasengan", "Charging"]          -> Just Debug
    ["Rasengan", "Hit"]               -> Just Info
    ["Ramen", "Ordered"]              -> Just Info
    ["Ramen", "Ichiraku", "Closed"]   -> Just Notice
    ["NineTails", "Chakra", "Leaking"] -> Just Warning
    ["Hokage", "Dream", "Declared"]   -> Just Notice
    _                                 -> Nothing
  documentFor _ = Just ""
  metricsDocFor (Namespace _ ["ShadowClone", "Spawned"]) =
    [("Naruto.shadowClones", "Shadow clones currently spawned")]
  metricsDocFor (Namespace _ ["Ramen", "Ordered"]) =
    [("Naruto.ramen.bowls", "Bowls of ramen ordered")]
  metricsDocFor _ = []
  allNamespaces = map (Namespace [])
    [ ["ShadowClone", "Spawned"], ["ShadowClone", "Dispelled"]
    , ["Rasengan", "Charging"], ["Rasengan", "Hit"]
    , ["Ramen", "Ordered"], ["Ramen", "Ichiraku", "Closed"]
    , ["NineTails", "Chakra", "Leaking"], ["Hokage", "Dream", "Declared"] ]

narutoEvents :: Events Naruto
narutoEvents =
  [ (30, ShadowCloneSpawned . int 1000)
  , (30, ShadowCloneDispelled . int 1000)
  , (20, RasenganCharging . double 100)
  , (5,  \w -> RasenganHit (pick ["Sasuke", "Pain", "Orochimaru", "Kaguya"] w) (int 9000 w))
  , (8,  RamenOrdered . int 12)
  , (1,  const RamenIchirakuClosed)
  , (1,  NineTailsChakraLeaking . double 10)
  , (1,  const HokageDreamDeclared) ]

-------------------------------------------------------------------------------
-- Kakashi

data Kakashi
  = SharinganActivated
  | SharinganCopied Text
  | ChidoriCharged Double
  | BookPageTurned Int
  | BookFinished
  | LateExcuseGiven Text
  | LateMinutes Int

instance LogFormatting Kakashi where
  forMachine _ = \case
    SharinganActivated -> kind "SharinganActivated"
    SharinganCopied j  -> kind "SharinganCopied" <> "jutsu" .= j
    ChidoriCharged c   -> kind "ChidoriCharged" <> "chakra" .= c
    BookPageTurned p   -> kind "BookPageTurned" <> "page" .= p
    BookFinished       -> kind "BookFinished"
    LateExcuseGiven e  -> kind "LateExcuseGiven" <> "excuse" .= e
    LateMinutes m      -> kind "LateMinutes" <> "minutes" .= m
  asMetrics = \case
    LateMinutes m -> [IntM "Kakashi.lateMinutes" (fromIntegral m)]
    _             -> []

instance MetaTrace Kakashi where
  namespaceFor = Namespace [] . \case
    SharinganActivated -> ["Sharingan", "Activated"]
    SharinganCopied {} -> ["Sharingan", "Copied"]
    ChidoriCharged {}  -> ["Chidori", "Charged"]
    BookPageTurned {}  -> ["Book", "Reading", "PageTurned"]
    BookFinished       -> ["Book", "Reading", "Finished"]
    LateExcuseGiven {} -> ["Late", "Excuse", "Given"]
    LateMinutes {}     -> ["Late", "Minutes"]
  severityFor (Namespace _ ns) _ = case ns of
    ["Sharingan", "Activated"]          -> Just Debug
    ["Sharingan", "Copied"]             -> Just Info
    ["Chidori", "Charged"]              -> Just Debug
    ["Book", "Reading", "PageTurned"]   -> Just Debug
    ["Book", "Reading", "Finished"]     -> Just Info
    ["Late", "Excuse", "Given"]         -> Just Info
    ["Late", "Minutes"]                 -> Just Info
    _                                   -> Nothing
  documentFor _ = Just ""
  metricsDocFor (Namespace _ ["Late", "Minutes"]) =
    [("Kakashi.lateMinutes", "Minutes late, most recently")]
  metricsDocFor _ = []
  allNamespaces = map (Namespace [])
    [ ["Sharingan", "Activated"], ["Sharingan", "Copied"], ["Chidori", "Charged"]
    , ["Book", "Reading", "PageTurned"], ["Book", "Reading", "Finished"]
    , ["Late", "Excuse", "Given"], ["Late", "Minutes"] ]

kakashiEvents :: Events Kakashi
kakashiEvents =
  [ (10, const SharinganActivated)
  , (3,  SharinganCopied . pick ["Chidori", "Water Dragon", "Kamui", "Fireball"])
  , (10, ChidoriCharged . double 100)
  , (40, BookPageTurned . int 300)
  , (1,  const BookFinished)
  , (2,  LateExcuseGiven . pick ["lost on the road of life", "a black cat", "helped an old lady"])
  , (2,  LateMinutes . int 180) ]

-------------------------------------------------------------------------------
-- Sailor Moon

data SailorMoon
  = TransformationStarted
  | TransformationCompleted
  | MoonTiaraThrown Text
  | MoonTiaraReturned
  | SpeechDelivered
  | SnackEaten Int
  | ExamFailed Int

instance LogFormatting SailorMoon where
  forMachine _ = \case
    TransformationStarted   -> kind "TransformationStarted"
    TransformationCompleted -> kind "TransformationCompleted"
    MoonTiaraThrown t       -> kind "MoonTiaraThrown" <> "target" .= t
    MoonTiaraReturned       -> kind "MoonTiaraReturned"
    SpeechDelivered         -> kind "SpeechDelivered"
    SnackEaten c            -> kind "SnackEaten" <> "calories" .= c
    ExamFailed s            -> kind "ExamFailed" <> "score" .= s
  asMetrics = \case
    SnackEaten c -> [CounterM "SailorMoon.snack.calories" (CounterAdd (fromIntegral c))]
    _            -> []

instance MetaTrace SailorMoon where
  namespaceFor = Namespace [] . \case
    TransformationStarted   -> ["Transformation", "Started"]
    TransformationCompleted -> ["Transformation", "Completed"]
    MoonTiaraThrown {}      -> ["MoonTiara", "Thrown"]
    MoonTiaraReturned       -> ["MoonTiara", "Returned"]
    SpeechDelivered         -> ["Speech", "Justice", "Delivered"]
    SnackEaten {}           -> ["Snack", "Eaten"]
    ExamFailed {}           -> ["Exam", "Failed"]
  severityFor (Namespace _ ns) _ = case ns of
    ["Transformation", "Started"]      -> Just Debug
    ["Transformation", "Completed"]    -> Just Info
    ["MoonTiara", "Thrown"]            -> Just Debug
    ["MoonTiara", "Returned"]          -> Just Debug
    ["Speech", "Justice", "Delivered"] -> Just Info
    ["Snack", "Eaten"]                 -> Just Debug
    ["Exam", "Failed"]                 -> Just Warning
    _                                  -> Nothing
  documentFor _ = Just ""
  metricsDocFor (Namespace _ ["Snack", "Eaten"]) =
    [("SailorMoon.snack.calories", "Calories eaten in snacks")]
  metricsDocFor _ = []
  allNamespaces = map (Namespace [])
    [ ["Transformation", "Started"], ["Transformation", "Completed"]
    , ["MoonTiara", "Thrown"], ["MoonTiara", "Returned"]
    , ["Speech", "Justice", "Delivered"], ["Snack", "Eaten"], ["Exam", "Failed"] ]

sailorMoonEvents :: Events SailorMoon
sailorMoonEvents =
  [ (5,  const TransformationStarted)
  , (5,  const TransformationCompleted)
  , (15, MoonTiaraThrown . pick ["Jadeite", "Nephrite", "Zoisite", "Kunzite", "Queen Beryl"])
  , (15, const MoonTiaraReturned)
  , (3,  const SpeechDelivered)
  , (25, SnackEaten . int 800)
  , (1,  ExamFailed . int 30) ]

-------------------------------------------------------------------------------
-- Sailor Mercury

data SailorMercury
  = ScanStarted
  | ScanProgress Double
  | ScanWeakPointFound Text
  | BubblesSprayed
  | StudySessionCompleted Double

instance LogFormatting SailorMercury where
  forMachine _ = \case
    ScanStarted             -> kind "ScanStarted"
    ScanProgress p          -> kind "ScanProgress" <> "percent" .= p
    ScanWeakPointFound w    -> kind "ScanWeakPointFound" <> "weakPoint" .= w
    BubblesSprayed          -> kind "BubblesSprayed"
    StudySessionCompleted h -> kind "StudySessionCompleted" <> "hours" .= h
  asMetrics = \case
    ScanProgress p -> [DoubleM "SailorMercury.scan.percent" p]
    _              -> []

instance MetaTrace SailorMercury where
  namespaceFor = Namespace [] . \case
    ScanStarted              -> ["Computer", "Scan", "Started"]
    ScanProgress {}          -> ["Computer", "Scan", "Progress"]
    ScanWeakPointFound {}    -> ["Computer", "Scan", "WeakPointFound"]
    BubblesSprayed           -> ["Bubbles", "Sprayed"]
    StudySessionCompleted {} -> ["Study", "Session", "Completed"]
  severityFor (Namespace _ ns) _ = case ns of
    ["Computer", "Scan", "Started"]        -> Just Debug
    ["Computer", "Scan", "Progress"]       -> Just Debug
    ["Computer", "Scan", "WeakPointFound"] -> Just Info
    ["Bubbles", "Sprayed"]                 -> Just Debug
    ["Study", "Session", "Completed"]      -> Just Info
    _                                      -> Nothing
  documentFor _ = Just ""
  metricsDocFor (Namespace _ ["Computer", "Scan", "Progress"]) =
    [("SailorMercury.scan.percent", "Progress of the current scan")]
  metricsDocFor _ = []
  allNamespaces = map (Namespace [])
    [ ["Computer", "Scan", "Started"], ["Computer", "Scan", "Progress"]
    , ["Computer", "Scan", "WeakPointFound"], ["Bubbles", "Sprayed"]
    , ["Study", "Session", "Completed"] ]

sailorMercuryEvents :: Events SailorMercury
sailorMercuryEvents =
  [ (5,  const ScanStarted)
  , (40, ScanProgress . double 100)
  , (3,  ScanWeakPointFound . pick ["left knee", "the crystal", "its shadow", "the third eye"])
  , (10, const BubblesSprayed)
  , (2,  StudySessionCompleted . double 8) ]

-------------------------------------------------------------------------------
-- Chihiro

data Chihiro
  = ChoreStarted Text
  | ChoreFinished Text
  | GuestServed Text
  | NameForgotten
  | NameRemembered
  | TrainBoarded

instance LogFormatting Chihiro where
  forMachine _ = \case
    ChoreStarted c  -> kind "ChoreStarted" <> "chore" .= c
    ChoreFinished c -> kind "ChoreFinished" <> "chore" .= c
    GuestServed g   -> kind "GuestServed" <> "guest" .= g
    NameForgotten   -> kind "NameForgotten"
    NameRemembered  -> kind "NameRemembered"
    TrainBoarded    -> kind "TrainBoarded"

chores :: [Text]
chores = ["scrubbing the big tub", "fetching herbal tokens", "boiler room", "cleaning the stink spirit"]

instance MetaTrace Chihiro where
  namespaceFor = Namespace [] . \case
    ChoreStarted {}  -> ["Bathhouse", "Chore", "Started"]
    ChoreFinished {} -> ["Bathhouse", "Chore", "Finished"]
    GuestServed {}   -> ["Bathhouse", "Guest", "Served"]
    NameForgotten    -> ["Name", "Forgotten"]
    NameRemembered   -> ["Name", "Remembered"]
    TrainBoarded     -> ["Train", "Boarded"]
  severityFor (Namespace _ ns) _ = case ns of
    ["Bathhouse", "Chore", "Started"]  -> Just Debug
    ["Bathhouse", "Chore", "Finished"] -> Just Debug
    ["Bathhouse", "Guest", "Served"]   -> Just Info
    ["Name", "Forgotten"]              -> Just Warning
    ["Name", "Remembered"]             -> Just Notice
    ["Train", "Boarded"]               -> Just Info
    _                                  -> Nothing
  documentFor _ = Just ""
  allNamespaces = map (Namespace [])
    [ ["Bathhouse", "Chore", "Started"], ["Bathhouse", "Chore", "Finished"]
    , ["Bathhouse", "Guest", "Served"], ["Name", "Forgotten"]
    , ["Name", "Remembered"], ["Train", "Boarded"] ]

chihiroEvents :: Events Chihiro
chihiroEvents =
  [ (30, ChoreStarted . pick chores)
  , (30, ChoreFinished . pick chores)
  , (10, GuestServed . pick ["River Spirit", "Radish Spirit", "Kamaji", "Yubaba"])
  , (1,  const NameForgotten)
  , (1,  const NameRemembered)
  , (1,  const TrainBoarded) ]

-------------------------------------------------------------------------------
-- No-Face

data NoFace
  = GoldOffered Int
  | FoodDevoured Int
  | SizeGrown Double
  | RampageStarted
  | RampageCalmed

instance LogFormatting NoFace where
  forMachine _ = \case
    GoldOffered n  -> kind "GoldOffered" <> "nuggets" .= n
    FoodDevoured d -> kind "FoodDevoured" <> "dishes" .= d
    SizeGrown s    -> kind "SizeGrown" <> "size" .= s
    RampageStarted -> kind "RampageStarted"
    RampageCalmed  -> kind "RampageCalmed"
  asMetrics = \case
    GoldOffered n  -> [CounterM "NoFace.gold.nuggets" (CounterAdd (fromIntegral n))]
    FoodDevoured d -> [IntM "NoFace.dishes" (fromIntegral d)]
    _              -> []

instance MetaTrace NoFace where
  namespaceFor = Namespace [] . \case
    GoldOffered {}  -> ["Gold", "Offered"]
    FoodDevoured {} -> ["Food", "Devoured"]
    SizeGrown {}    -> ["Size", "Grown"]
    RampageStarted  -> ["Rampage", "Started"]
    RampageCalmed   -> ["Rampage", "Calmed"]
  severityFor (Namespace _ ns) _ = case ns of
    ["Gold", "Offered"]   -> Just Debug
    ["Food", "Devoured"]  -> Just Debug
    ["Size", "Grown"]     -> Just Info
    ["Rampage", "Started"] -> Just Warning
    ["Rampage", "Calmed"] -> Just Notice
    _                     -> Nothing
  documentFor _ = Just ""
  metricsDocFor (Namespace _ ["Gold", "Offered"]) =
    [("NoFace.gold.nuggets", "Gold nuggets offered")]
  metricsDocFor (Namespace _ ["Food", "Devoured"]) =
    [("NoFace.dishes", "Dishes devoured in the last feast")]
  metricsDocFor _ = []
  allNamespaces = map (Namespace [])
    [ ["Gold", "Offered"], ["Food", "Devoured"], ["Size", "Grown"]
    , ["Rampage", "Started"], ["Rampage", "Calmed"] ]

noFaceEvents :: Events NoFace
noFaceEvents =
  [ (20, GoldOffered . int 50)
  , (20, FoodDevoured . int 40)
  , (3,  SizeGrown . double 20)
  , (1,  const RampageStarted)
  , (1,  const RampageCalmed) ]

-------------------------------------------------------------------------------
-- Goku

data Goku
  = GravityIncreased Int
  | PowerLevelMeasured Int
  | PowerLevelOver9000
  | KamehamehaCharging Double
  | KamehamehaFired
  | SuperSaiyanTransformed Int
  | MealEaten Int
  | SenzuEaten

instance LogFormatting Goku where
  forMachine _ = \case
    GravityIncreased g       -> kind "GravityIncreased" <> "gravity" .= g
    PowerLevelMeasured p     -> kind "PowerLevelMeasured" <> "powerLevel" .= p
    PowerLevelOver9000       -> kind "PowerLevelOver9000"
    KamehamehaCharging k     -> kind "KamehamehaCharging" <> "ki" .= k
    KamehamehaFired          -> kind "KamehamehaFired"
    SuperSaiyanTransformed l -> kind "SuperSaiyanTransformed" <> "level" .= l
    MealEaten p              -> kind "MealEaten" <> "plates" .= p
    SenzuEaten               -> kind "SenzuEaten"
  asMetrics = \case
    GravityIncreased g   -> [IntM "Goku.gravity" (fromIntegral g)]
    PowerLevelMeasured p -> [IntM "Goku.powerLevel" (fromIntegral p)]
    MealEaten p          -> [CounterM "Goku.plates" (CounterAdd (fromIntegral p))]
    _                    -> []

instance MetaTrace Goku where
  namespaceFor = Namespace [] . \case
    GravityIncreased {}       -> ["Training", "Gravity", "Increased"]
    PowerLevelMeasured {}     -> ["Training", "PowerLevel", "Measured"]
    PowerLevelOver9000        -> ["Training", "PowerLevel", "Over9000"]
    KamehamehaCharging {}     -> ["Kamehameha", "Charging"]
    KamehamehaFired           -> ["Kamehameha", "Fired"]
    SuperSaiyanTransformed {} -> ["SuperSaiyan", "Transformed"]
    MealEaten {}              -> ["Meal", "Eaten"]
    SenzuEaten                -> ["Senzu", "Eaten"]
  severityFor (Namespace _ ns) _ = case ns of
    ["Training", "Gravity", "Increased"]    -> Just Debug
    ["Training", "PowerLevel", "Measured"]  -> Just Debug
    ["Training", "PowerLevel", "Over9000"]  -> Just Notice
    ["Kamehameha", "Charging"]              -> Just Debug
    ["Kamehameha", "Fired"]                 -> Just Info
    ["SuperSaiyan", "Transformed"]          -> Just Info
    ["Meal", "Eaten"]                       -> Just Debug
    ["Senzu", "Eaten"]                      -> Just Info
    _                                       -> Nothing
  documentFor _ = Just ""
  metricsDocFor (Namespace _ ["Training", "Gravity", "Increased"]) =
    [("Goku.gravity", "Gravity in the training room, in g")]
  metricsDocFor (Namespace _ ["Training", "PowerLevel", "Measured"]) =
    [("Goku.powerLevel", "Last measured power level")]
  metricsDocFor (Namespace _ ["Meal", "Eaten"]) =
    [("Goku.plates", "Plates eaten")]
  metricsDocFor _ = []
  allNamespaces = map (Namespace [])
    [ ["Training", "Gravity", "Increased"], ["Training", "PowerLevel", "Measured"]
    , ["Training", "PowerLevel", "Over9000"], ["Kamehameha", "Charging"]
    , ["Kamehameha", "Fired"], ["SuperSaiyan", "Transformed"]
    , ["Meal", "Eaten"], ["Senzu", "Eaten"] ]

gokuEvents :: Events Goku
gokuEvents =
  [ (15, GravityIncreased . int 500)
  , (30, PowerLevelMeasured . int 150000)
  , (1,  const PowerLevelOver9000)
  , (15, KamehamehaCharging . double 100)
  , (4,  const KamehamehaFired)
  , (1,  SuperSaiyanTransformed . (+ 1) . int 3)
  , (20, MealEaten . int 60)
  , (1,  const SenzuEaten) ]

-------------------------------------------------------------------------------
-- Vegeta

data Vegeta
  = PrideWounded Text
  | RivalryDeclared
  | GalickGunFired
  | GravityRoomSession Int
  | ScouterReading Int
  | ScouterCrushed

instance LogFormatting Vegeta where
  forMachine _ = \case
    PrideWounded b       -> kind "PrideWounded" <> "byWhom" .= b
    RivalryDeclared      -> kind "RivalryDeclared"
    GalickGunFired       -> kind "GalickGunFired"
    GravityRoomSession g -> kind "GravityRoomSession" <> "gravity" .= g
    ScouterReading p     -> kind "ScouterReading" <> "powerLevel" .= p
    ScouterCrushed       -> kind "ScouterCrushed"

instance MetaTrace Vegeta where
  namespaceFor = Namespace [] . \case
    PrideWounded {}       -> ["Pride", "Wounded"]
    RivalryDeclared       -> ["Rivalry", "Declared"]
    GalickGunFired        -> ["GalickGun", "Fired"]
    GravityRoomSession {} -> ["Training", "GravityRoom", "Session"]
    ScouterReading {}     -> ["Scouter", "Reading"]
    ScouterCrushed        -> ["Scouter", "Crushed"]
  severityFor (Namespace _ ns) _ = case ns of
    ["Pride", "Wounded"]                 -> Just Info
    ["Rivalry", "Declared"]              -> Just Notice
    ["GalickGun", "Fired"]               -> Just Info
    ["Training", "GravityRoom", "Session"] -> Just Debug
    ["Scouter", "Reading"]               -> Just Debug
    ["Scouter", "Crushed"]               -> Just Warning
    _                                    -> Nothing
  documentFor _ = Just ""
  allNamespaces = map (Namespace [])
    [ ["Pride", "Wounded"], ["Rivalry", "Declared"], ["GalickGun", "Fired"]
    , ["Training", "GravityRoom", "Session"], ["Scouter", "Reading"]
    , ["Scouter", "Crushed"] ]

vegetaEvents :: Events Vegeta
vegetaEvents =
  [ (3,  PrideWounded . pick ["Kakarot", "Frieza", "Beerus", "Bulma"])
  , (1,  const RivalryDeclared)
  , (3,  const GalickGunFired)
  , (25, GravityRoomSession . int 500)
  , (25, ScouterReading . int 150000)
  , (1,  const ScouterCrushed) ]

-------------------------------------------------------------------------------
-- Eren

data Eren
  = TitanShifted
  | HardeningApplied Text
  | GasConsumed Double
  | AnchorFired
  | WallBreachDetected Text
  | RumblingStarted
  | VowDeclared

instance LogFormatting Eren where
  forMachine _ = \case
    TitanShifted         -> kind "TitanShifted"
    HardeningApplied a   -> kind "HardeningApplied" <> "area" .= a
    GasConsumed l        -> kind "GasConsumed" <> "liters" .= l
    AnchorFired          -> kind "AnchorFired"
    WallBreachDetected w -> kind "WallBreachDetected" <> "wall" .= w
    RumblingStarted      -> kind "RumblingStarted"
    VowDeclared          -> kind "VowDeclared"
  asMetrics = \case
    GasConsumed l -> [DoubleM "Eren.odm.gas" l]
    _             -> []

instance MetaTrace Eren where
  namespaceFor = Namespace [] . \case
    TitanShifted          -> ["Titan", "Shifted"]
    HardeningApplied {}   -> ["Titan", "Hardening", "Applied"]
    GasConsumed {}        -> ["ODM", "Gear", "Gas", "Consumed"]
    AnchorFired           -> ["ODM", "Gear", "Anchor", "Fired"]
    WallBreachDetected {} -> ["Wall", "Breach", "Detected"]
    RumblingStarted       -> ["Rumbling", "Started"]
    VowDeclared           -> ["Vow", "Declared"]
  severityFor (Namespace _ ns) _ = case ns of
    ["Titan", "Shifted"]                -> Just Info
    ["Titan", "Hardening", "Applied"]   -> Just Debug
    ["ODM", "Gear", "Gas", "Consumed"]  -> Just Debug
    ["ODM", "Gear", "Anchor", "Fired"]  -> Just Debug
    ["Wall", "Breach", "Detected"]      -> Just Warning
    ["Rumbling", "Started"]             -> Just Error
    ["Vow", "Declared"]                 -> Just Notice
    _                                   -> Nothing
  documentFor _ = Just ""
  metricsDocFor (Namespace _ ["ODM", "Gear", "Gas", "Consumed"]) =
    [("Eren.odm.gas", "Gas consumed by the ODM gear, in liters")]
  metricsDocFor _ = []
  allNamespaces = map (Namespace [])
    [ ["Titan", "Shifted"], ["Titan", "Hardening", "Applied"]
    , ["ODM", "Gear", "Gas", "Consumed"], ["ODM", "Gear", "Anchor", "Fired"]
    , ["Wall", "Breach", "Detected"], ["Rumbling", "Started"], ["Vow", "Declared"] ]

erenEvents :: Events Eren
erenEvents =
  [ (3,  const TitanShifted)
  , (10, HardeningApplied . pick ["fists", "nape", "teeth", "crystal"])
  , (30, GasConsumed . double 5)
  , (30, const AnchorFired)
  , (1,  WallBreachDetected . pick ["Maria", "Rose", "Sina"])
  , (1,  const RumblingStarted)
  , (1,  const VowDeclared) ]

-------------------------------------------------------------------------------
-- Levi

data Levi
  = SpinAttack Int
  | BladeReplaced
  | RoomInspected Int
  | RoomApproved
  | TeaSipped
  | OrderGiven Text

instance LogFormatting Levi where
  forMachine _ = \case
    SpinAttack t    -> kind "SpinAttack" <> "titans" .= t
    BladeReplaced   -> kind "BladeReplaced"
    RoomInspected d -> kind "RoomInspected" <> "dustSpots" .= d
    RoomApproved    -> kind "RoomApproved"
    TeaSipped       -> kind "TeaSipped"
    OrderGiven o    -> kind "OrderGiven" <> "order" .= o
  asMetrics = \case
    SpinAttack t    -> [CounterM "Levi.titans" (CounterAdd (fromIntegral t))]
    RoomInspected d -> [IntM "Levi.dustSpots" (fromIntegral d)]
    _               -> []

instance MetaTrace Levi where
  namespaceFor = Namespace [] . \case
    SpinAttack {}    -> ["ODM", "Gear", "Spin", "Attack"]
    BladeReplaced    -> ["ODM", "Gear", "Blade", "Replaced"]
    RoomInspected {} -> ["Cleaning", "Room", "Inspected"]
    RoomApproved     -> ["Cleaning", "Room", "Approved"]
    TeaSipped        -> ["Tea", "Sipped"]
    OrderGiven {}    -> ["Squad", "Order", "Given"]
  severityFor (Namespace _ ns) _ = case ns of
    ["ODM", "Gear", "Spin", "Attack"]    -> Just Info
    ["ODM", "Gear", "Blade", "Replaced"] -> Just Debug
    ["Cleaning", "Room", "Inspected"]    -> Just Debug
    ["Cleaning", "Room", "Approved"]     -> Just Info
    ["Tea", "Sipped"]                    -> Just Debug
    ["Squad", "Order", "Given"]          -> Just Info
    _                                    -> Nothing
  documentFor _ = Just ""
  metricsDocFor (Namespace _ ["ODM", "Gear", "Spin", "Attack"]) =
    [("Levi.titans", "Titans slain")]
  metricsDocFor (Namespace _ ["Cleaning", "Room", "Inspected"]) =
    [("Levi.dustSpots", "Dust spots found in the last inspection")]
  metricsDocFor _ = []
  allNamespaces = map (Namespace [])
    [ ["ODM", "Gear", "Spin", "Attack"], ["ODM", "Gear", "Blade", "Replaced"]
    , ["Cleaning", "Room", "Inspected"], ["Cleaning", "Room", "Approved"]
    , ["Tea", "Sipped"], ["Squad", "Order", "Given"] ]

leviEvents :: Events Levi
leviEvents =
  [ (5,  SpinAttack . int 5)
  , (10, const BladeReplaced)
  , (25, RoomInspected . int 30)
  , (2,  const RoomApproved)
  , (20, const TeaSipped)
  , (3,  OrderGiven . pick ["Dedicate your hearts", "Clean it again", "Don't die", "Choose"]) ]

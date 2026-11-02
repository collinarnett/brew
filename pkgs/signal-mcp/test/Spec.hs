module Main (main) where

import Control.Monad (forM_, when)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.ByteString.Lazy.Char8 qualified as LBC
import Data.Foldable (foldlM)
import Data.List (sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing, mapMaybe)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as T
import Hedgehog hiding (Command, Group)
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import System.FilePath (replaceExtension, takeBaseName)
import Test.Tasty
import Test.Tasty.Golden (findByExtension, goldenVsString)
import Test.Tasty.Hedgehog (testProperty)

import SignalMcp.Conversation
import SignalMcp.Envelope
import SignalMcp.Store

main :: IO ()
main = do
  envelopes <- findByExtension [".json"] "test/golden"
  defaultMain $
    testGroup
      "signal-mcp"
      [ testGroup "conversation ids" conversationProperties
      , testGroup "envelope events" envelopeProperties
      , testGroup "envelope golden" (map envelopeGolden envelopes)
      , testGroup "store" storeProperties
      ]

-- Ids ---------------------------------------------------------------------

uuids :: [ServiceId]
uuids =
  mapMaybe
    (either (const Nothing) Just . parseServiceId)
    [ "0b5c1c43-4a5e-4b3e-9c6e-6d1b0f6f1a01"
    , "1c6d2d54-5b6f-4c4f-8d7f-7e2c1f7f2b02"
    , "2d7e3e65-6c70-4d50-9e80-8f3d2f803c03"
    , "+15555550104"
    ]

groups :: [GroupId]
groups =
  mapMaybe
    (either (const Nothing) Just . parseGroupId)
    ["Pmpi+EfPWmsxiomLe9Nx2XF9HOE483p6iKiFj65iMwI=", "AAAAbbbbCCCCddddEEEEffffGGGGhhhhIIIIjjjjKKK="]

genServiceId :: Gen ServiceId
genServiceId = Gen.element uuids

genConversation :: Gen Conversation
genConversation = Gen.choice [Direct <$> genServiceId, Group <$> Gen.element groups]

-- | Few distinct values, so generated events keep landing on the same
-- messages.
genTimestamp :: Gen Timestamp
genTimestamp = Timestamp . (* 1000) <$> Gen.int64 (Range.linear 1 12)

-- | Drawn from fewer timestamps still, so posts, edits, deletes and
-- reactions keep meeting on the same message.
genKey :: Gen MessageKey
genKey = MessageKey <$> genServiceId <*> (Timestamp . (* 1000) <$> Gen.int64 (Range.constant 1 4))

conversationProperties :: [TestTree]
conversationProperties =
  [ testProperty "parse inverts render" . property $ do
      conversation <- forAll genConversation
      parseConversation (renderConversation conversation) === Right conversation
  , testProperty "a uuid parses whatever its case, to one id" . property $ do
      sid <- forAll (Gen.element (take 3 uuids))
      parseServiceId (T.toUpper (serviceIdText sid)) === Right sid
  , testProperty "text without a known prefix is refused" . property $ do
      raw <- forAll (Gen.text (Range.linear 0 30) Gen.unicode)
      when (any (`T.isPrefixOf` raw) ["user:", "group:"]) discard
      assert (either (const True) (const False) (parseConversation raw))
  ]

-- Envelopes ---------------------------------------------------------------

genAttachment :: Gen Attachment
genAttachment =
  Attachment
    <$> Gen.element ["image/jpeg", "application/pdf"]
    <*> Gen.maybe (Gen.element ["a.jpg", "b.pdf"])
    <*> Gen.maybe (Gen.int64 (Range.linear 0 100000))

genWord :: Gen Text
genWord = Gen.element ["lunch", "tomorrow", "kayak", "ferry", "café", "rent"]

genBody :: Gen Text
genBody = T.unwords <$> Gen.list (Range.linear 1 4) genWord

genDataMessage :: Gen DataMessage
genDataMessage =
  DataMessage
    <$> genTimestamp
    <*> Gen.maybe genBody
    <*> Gen.element [0, 0, 5, 604800]
    <*> Gen.bool
    <*> Gen.bool
    <*> Gen.list (Range.linear 0 2) genAttachment
    <*> Gen.bool
    <*> Gen.maybe (Quote <$> genServiceId <*> genTimestamp <*> Gen.maybe genBody)
    <*> Gen.maybe (Reaction <$> Gen.element ["👍", "❤️"] <*> genKey <*> Gen.bool)
    <*> Gen.maybe genTimestamp
    <*> Gen.maybe ((,) <$> Gen.element groups <*> Gen.maybe (Gen.element ["Climbing", "Family"]))

genDirection :: Gen Direction
genDirection = Gen.choice [pure FromSource, ToDestination <$> Gen.maybe genServiceId]

genEnvelope :: Gen Envelope
genEnvelope =
  Envelope
    <$> genServiceId
    <*> Gen.maybe (Gen.element ["Ana", "Bo", ""])
    <*> Gen.choice
      [ Data <$> genDirection <*> genDataMessage
      , Edit <$> genDirection <*> genTimestamp <*> genDataMessage
      , pure Ignored
      ]

posted :: [Event] -> [Message]
posted events = [m | Posted m <- events]

envelopeProperties :: [TestTree]
envelopeProperties =
  [ testProperty "every change is attributed to the envelope's source" . property $ do
      envelope <- forAll genEnvelope
      let authors = mapMaybe changedBy (envelopeEvents envelope)
      assert (all (== envelopeSource envelope) authors)
  , testProperty "view-once content never reaches the history" . property $ do
      envelope <- forAll genEnvelope
      forM_ (posted (envelopeEvents envelope)) $ \m ->
        when (messageViewOnce m) $ do
          messageBody m === Nothing
          messageAttachments m === []
  , testProperty "a message lands in its group, else with the other party" . property $ do
      direction <- forAll genDirection
      dm <- forAll genDataMessage
      source <- forAll genServiceId
      let expected = case (dataGroup dm, direction) of
            (Just (gid, _), _) -> Just (Group gid)
            (Nothing, FromSource) -> Just (Direct source)
            (Nothing, ToDestination destination) -> Direct <$> destination
      forM_ (posted (envelopeEvents (Envelope source Nothing (Data direction dm)))) $ \m ->
        Just (messageConversation m) === expected
  , testProperty "a sent message with no recipient or group is not recorded" . property $ do
      dm <- forAll ((\d -> d {dataGroup = Nothing}) <$> genDataMessage)
      source <- forAll genServiceId
      posted (envelopeEvents (Envelope source Nothing (Data (ToDestination Nothing) dm))) === []
  , testProperty "a disappearing message expires no later than its timer from sending" . property $ do
      envelope <- forAll genEnvelope
      forM_ [(dm, m) | Data _ dm <- [envelopeContent envelope], m <- posted (envelopeEvents envelope)] $ \(dm, m) ->
        messageExpiresAt m === expiresAt (dataSentAt dm) (dataExpiresInSeconds dm)
  ]
  where
    changedBy = \case
      Posted m -> Just (keyAuthor (messageKey m))
      Edited key _ -> Just (keyAuthor key)
      Deleted key -> Just (keyAuthor key)
      Reacted reactor _ _ -> Just reactor
      Unreacted reactor _ -> Just reactor
      _ -> Nothing

envelopeGolden :: FilePath -> TestTree
envelopeGolden path =
  goldenVsString (takeBaseName path) (replaceExtension path ".events") $ do
    raw <- LBS.readFile path
    pure $ case Aeson.eitherDecode raw of
      Left err -> LBC.pack ("parse error: " <> err <> "\n")
      Right envelope -> LBC.unlines (map (LBC.pack . show) (envelopeEvents envelope))

-- Store against a model ----------------------------------------------------

data Stored = Stored
  { storedMessage :: Message
  , storedEdited :: Bool
  , storedDeleted :: Bool
  }

data Model = Model
  { modelMessages :: Map MessageKey Stored
  , modelReactions :: Map (MessageKey, ServiceId) Text
  , modelContactNames :: Map ServiceId Text
  , modelProfileNames :: Map ServiceId Text
  , modelGroupNames :: Map GroupId Text
  , modelSelf :: Maybe ServiceId
  }

emptyModel :: Model
emptyModel = Model Map.empty Map.empty Map.empty Map.empty Map.empty Nothing

applyModel :: Model -> Event -> Model
applyModel model = \case
  Posted m -> model {modelMessages = Map.insertWith (\_ old -> old) (messageKey m) (Stored m False False) (modelMessages model)}
  Edited key body -> model {modelMessages = Map.adjust (edit body) key (modelMessages model)}
  Deleted key ->
    model
      { modelMessages = Map.adjust remove key (modelMessages model)
      , modelReactions = Map.filterWithKey (\(target, _) _ -> target /= key) (modelReactions model)
      }
  Reacted reactor key emoji -> model {modelReactions = Map.insert (key, reactor) emoji (modelReactions model)}
  Unreacted reactor key -> model {modelReactions = Map.delete (key, reactor) (modelReactions model)}
  PersonNamed sid name -> model {modelProfileNames = Map.insert sid name (modelProfileNames model)}
  ContactNamed sid name -> model {modelContactNames = Map.insert sid name (modelContactNames model)}
  GroupNamed gid name -> model {modelGroupNames = Map.insert gid name (modelGroupNames model)}
  where
    edit body s
      | storedDeleted s = s
      | otherwise = s {storedMessage = (storedMessage s) {messageBody = body}, storedEdited = True}
    remove s =
      s
        { storedMessage = (storedMessage s) {messageBody = Nothing, messageAttachments = [], messageQuote = Nothing}
        , storedDeleted = True
        }

purgeModel :: Timestamp -> Model -> Model
purgeModel now model =
  model
    { modelMessages = live
    , modelReactions = Map.filterWithKey (\(target, _) _ -> Map.member target live) (modelReactions model)
    }
  where
    live = Map.filter (not . expired now) (modelMessages model)

expired :: Timestamp -> Stored -> Bool
expired now s = maybe False (<= now) (messageExpiresAt (storedMessage s))

personName :: Model -> ServiceId -> Maybe Text
personName model sid = case Map.lookup sid (modelContactNames model) of
  Just name -> Just name
  Nothing -> Map.lookup sid (modelProfileNames model)

modelView :: Model -> Stored -> MessageView
modelView model s =
  MessageView
    { viewConversation = messageConversation m
    , viewKey = key
    , viewAuthorName = personName model (keyAuthor key)
    , viewFromSelf = modelSelf model == Just (keyAuthor key)
    , viewBody = messageBody m
    , viewAttachments = messageAttachments m
    , viewViewOnce = messageViewOnce m
    , viewQuote = messageQuote m
    , viewEdited = storedEdited s
    , viewDeleted = storedDeleted s
    , viewReactions =
        [ ReactionView reactor (personName model reactor) emoji
        | ((target, reactor), emoji) <- Map.toList (modelReactions model)
        , target == key
        ]
    }
  where
    m = storedMessage s
    key = messageKey m

newestFirst :: [MessageView] -> [MessageView]
newestFirst = sortOn (\v -> (Down (keySentAt (viewKey v)), keyAuthor (viewKey v)))

modelConversation :: Model -> Timestamp -> Conversation -> [MessageView]
modelConversation model now conversation =
  newestFirst
    [ modelView model s
    | s <- Map.elems (modelMessages model)
    , not (expired now s)
    , messageConversation (storedMessage s) == conversation
    ]

modelSummaries :: Model -> Timestamp -> [ConversationSummary]
modelSummaries model now =
  sortOn
    (\s -> (Down (summaryLastMessageAt s), renderConversation (summaryConversation s)))
    [ ConversationSummary conversation (name conversation) (maximum stamps) (length stamps)
    | (conversation, stamps) <- Map.toList grouped
    ]
  where
    grouped =
      Map.fromListWith
        (<>)
        [ (messageConversation (storedMessage s), [keySentAt (messageKey (storedMessage s))])
        | s <- Map.elems (modelMessages model)
        , not (expired now s)
        ]
    name = \case
      Direct sid -> personName model sid
      Group gid -> Map.lookup gid (modelGroupNames model)

genMessage :: Gen Message
genMessage =
  Message
    <$> genConversation
    <*> genKey
    <*> Gen.maybe genBody
    <*> Gen.list (Range.linear 0 2) genAttachment
    <*> Gen.bool
    <*> Gen.maybe (Quote <$> genServiceId <*> genTimestamp <*> Gen.maybe genBody)
    <*> Gen.maybe genTimestamp

genEvent :: Gen Event
genEvent =
  Gen.frequency
    [ (6, Posted <$> genMessage)
    , (2, Edited <$> genKey <*> Gen.maybe genBody)
    , (1, Deleted <$> genKey)
    , (2, Reacted <$> genServiceId <*> genKey <*> Gen.element ["👍", "❤️", "😂"])
    , (1, Unreacted <$> genServiceId <*> genKey)
    , (1, PersonNamed <$> genServiceId <*> Gen.element ["Ana", "Bo"])
    , (1, ContactNamed <$> genServiceId <*> Gen.element ["Ana Lima", "Bo (work)"])
    , (1, GroupNamed <$> Gen.element groups <*> Gen.element ["Climbing", "Family"])
    ]

data Command
  = Apply [Event]
  | Purge Timestamp
  | SetSelf ServiceId
  deriving stock (Show)

genCommand :: Gen Command
genCommand =
  Gen.frequency
    [ (8, Apply <$> Gen.list (Range.linear 1 4) genEvent)
    , (1, Purge <$> genTimestamp)
    , (1, SetSelf <$> genServiceId)
    ]

runCommand :: Store -> Model -> Command -> IO Model
runCommand store model = \case
  Apply events -> applyEvents store events >> pure (foldl applyModel model events)
  Purge now -> purgeExpired store now >> pure (purgeModel now model)
  SetSelf sid -> recordSelf store sid >> pure model {modelSelf = Just sid}

withMemoryStore :: (Store -> PropertyT IO a) -> PropertyT IO a
withMemoryStore action = do
  store <- liftIO (openWritable ":memory:")
  result <- action store
  liftIO (closeStore store)
  pure result

limitOf :: Int -> PropertyT IO ResultLimit
limitOf = evalEither . parseResultLimit

storeProperties :: [TestTree]
storeProperties =
  [ testProperty "every conversation reads as the model does after any commands" . property $ do
      commands <- forAll (Gen.list (Range.linear 0 25) genCommand)
      now <- forAll genTimestamp
      withMemoryStore $ \store -> do
        everyMessage <- limitOf 200
        model <- liftIO (foldlM (runCommand store) emptyModel commands)
        forM_ (conversationsIn model) $ \conversation -> do
          stored <- liftIO (readConversation store now conversation Nothing everyMessage)
          stored === modelConversation model now conversation
        summaries <- liftIO (listConversations store now everyMessage)
        summaries === modelSummaries model now
  , testProperty "a limit and a before time page through the same list" . property $ do
      events <- forAll (Gen.list (Range.linear 0 30) genEvent)
      conversation <- forAll genConversation
      limit <- forAll (Gen.int (Range.linear 1 10))
      before <- forAll (Gen.maybe genTimestamp)
      withMemoryStore $ \store -> do
        everyMessage <- limitOf 200
        liftIO (applyEvents store events)
        let now = Timestamp 0
        everything <- liftIO (readConversation store now conversation Nothing everyMessage)
        pageLimit <- limitOf limit
        page <- liftIO (readConversation store now conversation before pageLimit)
        page === take limit [v | v <- everything, maybe True (keySentAt (viewKey v) <) before]
  , testProperty "purging changes nothing a reader at that time can see" . property $ do
      events <- forAll (Gen.list (Range.linear 0 30) genEvent)
      now <- forAll genTimestamp
      withMemoryStore $ \store -> do
        everyMessage <- limitOf 200
        liftIO (applyEvents store events)
        let readAll = liftIO $ (,) <$> listConversations store now everyMessage <*> traverse (\c -> readConversation store now c Nothing everyMessage) allConversations
        unpurged <- readAll
        liftIO (purgeExpired store now)
        purged <- readAll
        unpurged === purged
  , testProperty "search finds a live message by any word of its body" . property $ do
      m <- forAll genMessage
      body <- forAll genBody
      word <- forAll (Gen.element (T.words body))
      let message = m {messageBody = Just body, messageExpiresAt = Nothing}
      withMemoryStore $ \store -> do
        everyMessage <- limitOf 200
        liftIO (applyEvents store [Posted message])
        terms <- evalEither (parseSearchText word)
        found <- liftIO (searchMessages store (Timestamp 0) terms Nothing everyMessage)
        map viewKey found === [messageKey message]
  , testProperty "no query text is read as FTS syntax" . property $ do
      raw <- forAll (Gen.text (Range.linear 1 30) (Gen.frequency [(3, Gen.unicode), (2, Gen.element ("\"*:^()-+ ANDORNOT" :: String))]))
      events <- forAll (Gen.list (Range.linear 0 10) genEvent)
      case parseSearchText raw of
        Left _ -> assert (T.null (T.strip raw))
        Right terms -> withMemoryStore $ \store -> do
          everyMessage <- limitOf 200
          liftIO (applyEvents store events)
          _ <- liftIO (searchMessages store (Timestamp 0) terms Nothing everyMessage)
          success
  , testProperty "an edit after a delete leaves the message deleted" . property $ do
      m <- forAll genMessage
      body <- forAll (Gen.maybe genBody)
      withMemoryStore $ \store -> do
        everyMessage <- limitOf 200
        liftIO (applyEvents store [Posted m {messageExpiresAt = Nothing}, Deleted (messageKey m), Edited (messageKey m) body])
        [view] <- liftIO (readConversation store (Timestamp 0) (messageConversation m) Nothing everyMessage)
        assert (viewDeleted view && isNothing (viewBody view))
  ]
  where
    allConversations = map Direct uuids <> map Group groups
    conversationsIn model = Map.keys (Map.fromList [(messageConversation (storedMessage s), ()) | s <- Map.elems (modelMessages model)]) <> allConversations


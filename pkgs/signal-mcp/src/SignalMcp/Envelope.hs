-- | signal-cli's received envelopes, and what each one changes in the
-- message history. Parsing keeps only what the history records; deciding
-- what an envelope means is pure and lives in 'envelopeEvents'.
module SignalMcp.Envelope
  ( Envelope (..)
  , Content (..)
  , Direction (..)
  , DataMessage (..)
  , Attachment (..)
  , signalAttachment
  , Quote (..)
  , Reaction (..)
  , MessageKey (..)
  , Message (..)
  , Event (..)
  , envelopeEvents
  , expiresAt
  ) where

import Control.Applicative ((<|>))
import Data.Aeson (FromJSON (..), ToJSON (..), Value, object, withObject, (.!=), (.:), (.:?), (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.Types (Object, Parser)
import Data.Int (Int64)
import Data.Maybe (isJust, maybeToList)
import Data.Text (Text)
import Data.Text qualified as T

import SignalMcp.Conversation

data Envelope = Envelope
  { envelopeSource :: ServiceId
  , envelopeSourceName :: Maybe Text
  , envelopeContent :: Content
  }
  deriving stock (Eq, Show)

-- | Which conversation a message outside any group belongs to: the
-- sender's, or for a message this account sent from another of its
-- devices, the recipient's.
data Direction
  = FromSource
  | ToDestination (Maybe ServiceId)
  deriving stock (Eq, Show)

data Content
  = Data Direction DataMessage
  | Edit Direction Timestamp DataMessage
  | Ignored
  deriving stock (Eq, Show)

data DataMessage = DataMessage
  { dataSentAt :: Timestamp
  , dataBody :: Maybe Text
  , dataExpiresInSeconds :: Int64
  , dataExpirationUpdate :: Bool
  , dataViewOnce :: Bool
  , dataAttachments :: [Attachment]
  , dataSticker :: Bool
  , dataQuote :: Maybe Quote
  , dataReaction :: Maybe Reaction
  , dataRemoteDelete :: Maybe Timestamp
  , dataGroup :: Maybe (GroupId, Maybe Text)
  }
  deriving stock (Eq, Show)

data Attachment = Attachment
  { attachmentContentType :: Text
  , attachmentFilename :: Maybe Text
  , attachmentSize :: Maybe Int64
  }
  deriving stock (Eq, Ord, Show)

-- | The history's own encoding, which is also what the read tools return.
instance ToJSON Attachment where
  toJSON a =
    object
      [ "content_type" .= attachmentContentType a
      , "filename" .= attachmentFilename a
      , "size" .= attachmentSize a
      ]

instance FromJSON Attachment where
  parseJSON = withObject "attachment" $ \o ->
    Attachment <$> o .: "content_type" <*> o .:? "filename" <*> o .:? "size"

data Quote = Quote
  { quoteAuthor :: ServiceId
  , quoteSentAt :: Timestamp
  , quoteText :: Maybe Text
  }
  deriving stock (Eq, Ord, Show)

data Reaction = Reaction
  { reactionEmoji :: Text
  , reactionTarget :: MessageKey
  , reactionRemove :: Bool
  }
  deriving stock (Eq, Show)

-- | Signal names a message by its author and sent timestamp; edits,
-- deletes, quotes and reactions all point at messages this way.
data MessageKey = MessageKey
  { keyAuthor :: ServiceId
  , keySentAt :: Timestamp
  }
  deriving stock (Eq, Ord, Show)

data Message = Message
  { messageConversation :: Conversation
  , messageKey :: MessageKey
  , messageBody :: Maybe Text
  , messageAttachments :: [Attachment]
  , messageViewOnce :: Bool
  , messageQuote :: Maybe Quote
  , messageExpiresAt :: Maybe Timestamp
  }
  deriving stock (Eq, Show)

data Event
  = Posted Message
  | Edited MessageKey (Maybe Text)
  | Deleted MessageKey
  | Reacted ServiceId MessageKey Text
  | Unreacted ServiceId MessageKey
  | PersonNamed ServiceId Text
  | -- | The name the account owner saved for someone, which reads ahead of
    -- the profile name they chose for themselves.
    ContactNamed ServiceId Text
  | GroupNamed GroupId Text
  deriving stock (Eq, Show)

envelopeEvents :: Envelope -> [Event]
envelopeEvents envelope = naming <> changes
  where
    source = envelopeSource envelope
    naming =
      [PersonNamed source name | Just name <- [envelopeSourceName envelope], not (T.null name)]
        <> [ GroupNamed gid name
           | Just dm <- [contentData (envelopeContent envelope)]
           , Just (gid, Just name) <- [dataGroup dm]
           , not (T.null name)
           ]
    changes = case envelopeContent envelope of
      Ignored -> []
      Edit _ target dm -> [Edited (MessageKey source target) (dataBody dm)]
      Data direction dm
        | Just deleted <- dataRemoteDelete dm -> [Deleted (MessageKey source deleted)]
        | Just reaction <- dataReaction dm ->
            [ if reactionRemove reaction
                then Unreacted source (reactionTarget reaction)
                else Reacted source (reactionTarget reaction) (reactionEmoji reaction)
            ]
        | dataExpirationUpdate dm -> []
        | otherwise -> Posted <$> maybeToList (message direction dm)
    message direction dm = do
      conversation <- case (dataGroup dm, direction) of
        (Just (gid, _), _) -> Just (Group gid)
        (Nothing, FromSource) -> Just (Direct source)
        (Nothing, ToDestination destination) -> Direct <$> destination
      let attachments =
            if dataViewOnce dm
              then []
              else dataAttachments dm <> [stickerAttachment | dataSticker dm]
          body = if dataViewOnce dm then Nothing else dataBody dm
      if isJust body || not (null attachments) || dataViewOnce dm
        then
          Just
            Message
              { messageConversation = conversation
              , messageKey = MessageKey source (dataSentAt dm)
              , messageBody = body
              , messageAttachments = attachments
              , messageViewOnce = dataViewOnce dm
              , messageQuote = dataQuote dm
              , messageExpiresAt = expiresAt (dataSentAt dm) (dataExpiresInSeconds dm)
              }
        else Nothing

-- | When a disappearing message must leave the history. Signal starts the
-- recipient's timer when the message is read, so counting from the send
-- time removes it no later than the owner's phone does.
expiresAt :: Timestamp -> Int64 -> Maybe Timestamp
expiresAt (Timestamp sentAt) seconds
  | seconds > 0 = Just (Timestamp (sentAt + seconds * 1000))
  | otherwise = Nothing

stickerAttachment :: Attachment
stickerAttachment = Attachment "application/x-signal-sticker" Nothing Nothing

contentData :: Content -> Maybe DataMessage
contentData = \case
  Data _ dm -> Just dm
  Edit _ _ dm -> Just dm
  Ignored -> Nothing

instance FromJSON Envelope where
  parseJSON = withObject "envelope" $ \o -> do
    source <- address o "sourceUuid" "sourceNumber" >>= maybe (fail "envelope has no source") pure
    name <- o .:? "sourceName"
    dataMessage <- o .:? "dataMessage"
    editMessage <- o .:? "editMessage"
    syncMessage <- o .:? "syncMessage"
    content <- case (dataMessage, editMessage, syncMessage) of
      (Just dm, _, _) -> Data FromSource <$> dataMessageP dm
      (_, Just em, _) -> editP FromSource em
      (_, _, Just sm) -> sm .:? "sentMessage" >>= maybe (pure Ignored) sentP
      _ -> pure Ignored
    pure (Envelope source name content)
    where
      sentP sent = do
        direction <- ToDestination <$> address sent "destinationUuid" "destinationNumber"
        sent .:? "editMessage" >>= \case
          Just em -> editP direction em
          -- signal-cli flattens the sent data message into this object.
          Nothing -> Data direction <$> dataMessageP sent
      editP direction em =
        Edit direction <$> (Timestamp <$> em .: "targetSentTimestamp") <*> (em .: "dataMessage" >>= dataMessageP)

dataMessageP :: Object -> Parser DataMessage
dataMessageP d =
  DataMessage
    <$> (Timestamp <$> d .: "timestamp")
    <*> (nonEmpty <$> d .:? "message")
    <*> d .:? "expiresInSeconds" .!= 0
    <*> d .:? "isExpirationUpdate" .!= False
    <*> d .:? "viewOnce" .!= False
    <*> (d .:? "attachments" .!= [] >>= traverse (withObject "attachment" signalAttachment))
    <*> (isJust <$> (d .:? "sticker" :: Parser (Maybe Value)))
    <*> (d .:? "quote" >>= traverse quoteP)
    <*> (d .:? "reaction" >>= traverse reactionP)
    <*> (d .:? "remoteDelete" >>= traverse (fmap Timestamp . (.: "timestamp")))
    <*> (d .:? "groupInfo" >>= traverse groupP)
  where
    quoteP q = do
      author <- address q "authorUuid" "authorNumber" >>= maybe (fail "quote has no author") pure
      Quote author <$> (Timestamp <$> q .: "id") <*> (nonEmpty <$> q .:? "text")
    reactionP r = do
      author <- address r "targetAuthorUuid" "targetAuthorNumber" >>= maybe (fail "reaction has no target author") pure
      target <- MessageKey author . Timestamp <$> r .: "targetSentTimestamp"
      Reaction <$> r .: "emoji" <*> pure target <*> r .:? "isRemove" .!= False
    groupP g = do
      gid <- g .: "groupId" >>= either (fail . T.unpack) pure . parseGroupId
      (,) gid . (>>= nonEmpty) <$> g .:? "groupName"

-- | signal-cli's attachment object.
signalAttachment :: Object -> Parser Attachment
signalAttachment a =
  Attachment
    <$> a .:? "contentType" .!= "application/octet-stream"
    <*> a .:? "filename"
    <*> a .:? "size"

-- | signal-cli sends an address as a uuid and a number, either of which can
-- be null; the uuid is the stable one.
address :: Object -> Text -> Text -> Parser (Maybe ServiceId)
address o uuidKey numberKey = do
  uuid <- o .:? Key.fromText uuidKey
  number <- o .:? Key.fromText numberKey
  case uuid <|> number of
    Nothing -> pure Nothing
    Just raw -> either (fail . T.unpack) (pure . Just) (parseServiceId raw)

nonEmpty :: Maybe Text -> Maybe Text
nonEmpty = \case
  Just t | not (T.null t) -> Just t
  _ -> Nothing

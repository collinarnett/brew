-- | Who a message belongs to. A conversation id is the one string the read
-- and send servers share: the reader lists them, the sender takes them back.
module SignalMcp.Conversation
  ( ServiceId
  , serviceIdText
  , parseServiceId
  , GroupId
  , groupIdText
  , parseGroupId
  , Conversation (..)
  , renderConversation
  , parseConversation
  , Timestamp (..)
  ) where

import Data.Char (isDigit, isHexDigit)
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as T
import Database.SQLite.Simple.FromField (FromField (..), ResultError (ConversionFailed), returnError)
import Database.SQLite.Simple.Ok (Ok (..))
import Database.SQLite.Simple.ToField (ToField (..))

-- | A Signal account as signal-cli addresses it: an ACI uuid, or an E.164
-- number for a contact whose uuid signal-cli has not learned.
newtype ServiceId = ServiceId Text
  deriving stock (Eq, Ord, Show)

serviceIdText :: ServiceId -> Text
serviceIdText (ServiceId sid) = sid

parseServiceId :: Text -> Either Text ServiceId
parseServiceId raw
  | isUuid raw = Right (ServiceId (T.toLower raw))
  | Just digits <- T.stripPrefix "+" raw
  , T.length digits >= 3
  , T.length digits <= 15
  , T.all isDigit digits =
      Right (ServiceId raw)
  | otherwise = Left ("not a Signal uuid or +E.164 number: " <> raw)
  where
    isUuid t =
      map T.length (T.splitOn "-" t) == [8, 4, 4, 4, 12]
        && T.all (\c -> c == '-' || isHexDigit c) t

-- | A group's base64 master id.
newtype GroupId = GroupId Text
  deriving stock (Eq, Ord, Show)

groupIdText :: GroupId -> Text
groupIdText (GroupId gid) = gid

parseGroupId :: Text -> Either Text GroupId
parseGroupId raw
  | not (T.null raw)
  , T.all (\c -> c `elem` base64Alphabet) raw =
      Right (GroupId raw)
  | otherwise = Left ("not a base64 group id: " <> raw)
  where
    base64Alphabet = ['A' .. 'Z'] <> ['a' .. 'z'] <> ['0' .. '9'] <> "+/="

data Conversation
  = Direct ServiceId
  | Group GroupId
  deriving stock (Eq, Ord, Show)

renderConversation :: Conversation -> Text
renderConversation = \case
  Direct sid -> "user:" <> serviceIdText sid
  Group gid -> "group:" <> groupIdText gid

parseConversation :: Text -> Either Text Conversation
parseConversation raw
  | Just sid <- T.stripPrefix "user:" raw = Direct <$> parseServiceId sid
  | Just gid <- T.stripPrefix "group:" raw = Group <$> parseGroupId gid
  | otherwise = Left ("not a conversation id as signal_list_conversations gives them: " <> raw)

-- | Milliseconds since the epoch. Signal identifies a message by its
-- author and the timestamp the author's device sent it with.
newtype Timestamp = Timestamp Int64
  deriving stock (Eq, Ord, Show)

-- The history stores each id as the text these functions render and parse.

instance ToField ServiceId where
  toField = toField . serviceIdText

instance FromField ServiceId where
  fromField field = fromField field >>= either (returnError ConversionFailed field . T.unpack) Ok . parseServiceId

instance ToField Conversation where
  toField = toField . renderConversation

instance FromField Conversation where
  fromField field = fromField field >>= either (returnError ConversionFailed field . T.unpack) Ok . parseConversation

instance ToField Timestamp where
  toField (Timestamp ms) = toField ms

instance FromField Timestamp where
  fromField field = Timestamp <$> fromField field

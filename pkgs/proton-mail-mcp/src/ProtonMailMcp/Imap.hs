-- | IMAP command arguments. HaskellNet splices strings into commands verbatim,
-- so a raw string holding a quote or a line break would let mail-derived text
-- issue commands of its own. 'ImapString' can only be built by
-- 'quoteImapString', which makes that unrepresentable.
module ProtonMailMcp.Imap
  ( ImapString
  , quoteImapString
  , renderImapString
  , FolderName
  , parseFolderName
  , renderFolderName
  , SearchCriteria (..)
  , emptyCriteria
  , SearchText
  , parseSearchText
  , searchTextMatches
  , needsHeaders
  , CommandPart (..)
  , serverSearchCommand
  , searchLineUids
  , headerBlockUid
  , ResultLimit
  , parseResultLimit
  , defaultResultLimit
  , Arrival (..)
  , arrivalFromLine
  , newestArrivals
  , fetchedSection
  ) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Char (isAscii, isControl, isDigit)
import Data.List (sortOn)
import Data.Maybe (catMaybes, isJust, listToMaybe)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (UTCTime, defaultTimeLocale, formatTime, parseTimeM)
import Data.Time.Calendar qualified
import Network.HaskellNet.IMAP.Types (UID)
import Text.Read (readMaybe)

-- | The escaped contents of an RFC 3501 quoted string.
newtype ImapString = ImapString String
  deriving stock (Eq, Show)

-- | RFC 3501 quoted strings hold 7-bit text without control characters.
quoteImapString :: Text -> Either Text ImapString
quoteImapString raw
  | T.any (not . isAscii) raw = Left ("IMAP text must be ASCII: " <> raw)
  | T.any isControl raw = Left "IMAP text must not hold control characters"
  | otherwise = Right (ImapString (concatMap escape (T.unpack raw)))
  where
    escape c
      | c == '"' || c == '\\' = ['\\', c]
      | otherwise = [c]

renderImapString :: ImapString -> String
renderImapString (ImapString escaped) = '"' : escaped <> "\""

newtype FolderName = FolderName ImapString
  deriving stock (Eq, Show)

parseFolderName :: Text -> Either Text FolderName
parseFolderName raw
  | T.null raw = Left "folder must not be empty"
  | otherwise = FolderName <$> quoteImapString raw

-- | The form HaskellNet's 'Network.HaskellNet.IMAP.examine' takes: it adds
-- the delimiters itself and escapes nothing.
renderFolderName :: FolderName -> String
renderFolderName (FolderName (ImapString escaped)) = escaped

-- | What to look for in a message. Bridge's SEARCH compares against stored
-- bytes without decoding them, so it cannot see inside an RFC 2047 encoded
-- header or a base64 body. From, To and Subject are therefore matched here
-- against decoded headers, and only the rest goes to the server.
data SearchCriteria = SearchCriteria
  { criteriaFrom :: Maybe SearchText
  , criteriaTo :: Maybe SearchText
  , criteriaSubject :: Maybe SearchText
  , criteriaText :: Maybe SearchText
  , criteriaSince :: Maybe Data.Time.Calendar.Day
  , criteriaBefore :: Maybe Data.Time.Calendar.Day
  , criteriaUnreadOnly :: Bool
  }
  deriving stock (Eq, Show)

emptyCriteria :: SearchCriteria
emptyCriteria = SearchCriteria Nothing Nothing Nothing Nothing Nothing Nothing False

newtype SearchText = SearchText Text
  deriving stock (Eq, Show)

parseSearchText :: Text -> Either Text SearchText
parseSearchText raw
  | T.null raw = Left "search text must not be empty"
  | T.any isControl raw = Left "search text must not hold control characters"
  | otherwise = Right (SearchText raw)

-- | Whether decoded header text contains the search text, ignoring case.
searchTextMatches :: SearchText -> Text -> Bool
searchTextMatches (SearchText wanted) decoded = T.toCaseFold wanted `T.isInfixOf` T.toCaseFold decoded

needsHeaders :: SearchCriteria -> Bool
needsHeaders criteria = any isJust [criteriaFrom criteria, criteriaTo criteria, criteriaSubject criteria]

-- | A command in the pieces it crosses the wire in: a literal must wait for
-- the server's go-ahead. Literals carry their length, so no search text can
-- end its own argument.
data CommandPart
  = Verbatim ByteString
  | Literal ByteString
  deriving stock (Eq, Show)

-- | The criteria Bridge can evaluate. Its TEXT match sees stored bytes, so it
-- misses words inside base64 or quoted-printable bodies.
serverSearchCommand :: SearchCriteria -> [CommandPart]
serverSearchCommand criteria =
  case criteriaText criteria of
    Just (SearchText wanted) ->
      [Verbatim "UID SEARCH CHARSET UTF-8 TEXT ", Literal (TE.encodeUtf8 wanted), Verbatim (BC.pack (concatMap (' ' :) keys))]
    Nothing -> [Verbatim (BC.pack (unwords ("UID SEARCH" : if null keys then ["ALL"] else keys)))]
  where
    keys =
      catMaybes
        [ ("SINCE " <>) . imapDate <$> criteriaSince criteria
        , ("BEFORE " <>) . imapDate <$> criteriaBefore criteria
        , if criteriaUnreadOnly criteria then Just "UNSEEN" else Nothing
        ]

imapDate :: Data.Time.Calendar.Day -> String
imapDate = formatTime defaultTimeLocale "%d-%b-%Y"

-- | The UIDs on a SEARCH response line, or Nothing for any other line.
searchLineUids :: ByteString -> Maybe [UID]
searchLineUids line = do
  rest <- BS.stripPrefix "* SEARCH" line
  traverse (readMaybe . BC.unpack) (BC.words rest)

-- | The UID in the text around a FETCH response's literal.
headerBlockUid :: ByteString -> Maybe UID
headerBlockUid surrounding =
  readMaybe (BC.unpack (BC.takeWhile isDigit (BS.drop 4 (snd (BS.breakSubstring "UID " surrounding)))))

newtype ResultLimit = ResultLimit Int
  deriving stock (Eq, Show)

parseResultLimit :: Int -> Either Text ResultLimit
parseResultLimit n
  | n < 1 || n > 100 = Left "limit must be between 1 and 100"
  | otherwise = Right (ResultLimit n)

defaultResultLimit :: ResultLimit
defaultResultLimit = ResultLimit 20

-- | The value of a BODY section among one FETCH response's items. Servers order
-- those freely: dovecot sends UID first, so HaskellNet glues @UID 5@ onto the
-- section's key, and Bridge sends the section first. Matching the key's last
-- word reads both.
fetchedSection :: String -> [(String, String)] -> Maybe String
fetchedSection section items =
  listToMaybe [value | (key, value) <- items, take 1 (reverse (words key)) == [section]]

-- | When a message reached the mailbox. UIDs say nothing about this: Bridge
-- imports newest mail first, so after its initial sync the highest UIDs hold
-- the oldest mail.
data Arrival = Arrival
  { arrivalUid :: UID
  , arrivalTime :: UTCTime
  }
  deriving stock (Eq, Show)

-- | Reads one line of the reply to a UID and INTERNALDATE fetch. Lines that are
-- not FETCH responses are other untagged news and yield Nothing. A FETCH line
-- without both items is an error, since sorting without it would silently
-- misplace that message.
arrivalFromLine :: ByteString -> Either Text (Maybe Arrival)
arrivalFromLine line
  | not (" FETCH (" `BS.isInfixOf` line) = Right Nothing
  | otherwise =
      maybe (Left ("unreadable FETCH response: " <> TE.decodeUtf8Lenient line)) (Right . Just) $
        Arrival <$> uidItem <*> dateItem
  where
    after marker = BS.drop (BS.length marker) (snd (BS.breakSubstring marker line))
    uidItem = readMaybe (BC.unpack (BC.takeWhile isDigit (after "UID ")))
    dateItem = internalDate (BC.unpack (BC.takeWhile (/= '"') (after "INTERNALDATE \"")))

internalDate :: String -> Maybe UTCTime
internalDate = parseTimeM True defaultTimeLocale "%e-%b-%Y %H:%M:%S %z"

newestArrivals :: ResultLimit -> [Arrival] -> [UID]
newestArrivals (ResultLimit limit) =
  map arrivalUid . take limit . sortOn (\arrival -> Down (arrivalTime arrival, arrivalUid arrival))

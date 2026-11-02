-- | The message history in SQLite. signal-cli keeps no history of its own,
-- so this file is the only record of what was said; the ingester writes it
-- and the read server opens it with writes refused.
module SignalMcp.Store
  ( Store
  , openWritable
  , openReadOnly
  , closeStore
  , applyEvents
  , recordSelf
  , purgeExpired
  , ResultLimit
  , parseResultLimit
  , defaultResultLimit
  , SearchText
  , parseSearchText
  , ftsQuery
  , ConversationSummary (..)
  , listConversations
  , ReactionView (..)
  , MessageView (..)
  , readConversation
  , searchMessages
  , findNames
  ) where

import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Control.Exception (throwIO)
import Control.Monad (forM, unless)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Database.SQLite.Simple
import System.Directory (doesFileExist)

import SignalMcp.Conversation
import SignalMcp.Envelope

newtype Store = Store (MVar Connection)

usingStore :: Store -> (Connection -> IO a) -> IO a
usingStore (Store conn) = withMVar conn

-- | Opens the history for the ingester and the send server, creating it on
-- first use.
openWritable :: FilePath -> IO Store
openWritable path = do
  conn <- open path
  execute_ conn "PRAGMA journal_mode = WAL"
  configure conn
  withTransaction conn (mapM_ (execute_ conn) schema)
  Store <$> newMVar conn

-- | Opens an existing history with every write refused by SQLite itself.
openReadOnly :: FilePath -> IO Store
openReadOnly path = do
  exists <- doesFileExist path
  unless exists $
    ioError (userError (path <> " does not exist yet: the signal-mcp ingester creates it when it first runs"))
  conn <- open path
  configure conn
  execute_ conn "PRAGMA query_only = ON"
  Store <$> newMVar conn

configure :: Connection -> IO ()
configure conn = do
  execute_ conn "PRAGMA busy_timeout = 5000"
  execute_ conn "PRAGMA foreign_keys = ON"

closeStore :: Store -> IO ()
closeStore store = usingStore store close

schema :: [Query]
schema =
  [ "CREATE TABLE IF NOT EXISTS messages (\
    \ id INTEGER PRIMARY KEY,\
    \ conversation TEXT NOT NULL,\
    \ author TEXT NOT NULL,\
    \ sent_at INTEGER NOT NULL,\
    \ body TEXT,\
    \ attachments TEXT NOT NULL,\
    \ view_once INTEGER NOT NULL,\
    \ quote_author TEXT,\
    \ quote_sent_at INTEGER,\
    \ quote_text TEXT,\
    \ expires_at INTEGER,\
    \ edited INTEGER NOT NULL DEFAULT 0,\
    \ deleted INTEGER NOT NULL DEFAULT 0,\
    \ UNIQUE (author, sent_at))"
  , "CREATE INDEX IF NOT EXISTS messages_by_conversation ON messages (conversation, sent_at)"
  , "CREATE VIRTUAL TABLE IF NOT EXISTS messages_text USING fts5 (body, content = 'messages', content_rowid = 'id')"
  , "CREATE TRIGGER IF NOT EXISTS messages_text_insert AFTER INSERT ON messages BEGIN\
    \ INSERT INTO messages_text (rowid, body) VALUES (new.id, new.body); END"
  , "CREATE TRIGGER IF NOT EXISTS messages_text_delete AFTER DELETE ON messages BEGIN\
    \ INSERT INTO messages_text (messages_text, rowid, body) VALUES ('delete', old.id, old.body); END"
  , "CREATE TRIGGER IF NOT EXISTS messages_text_update AFTER UPDATE OF body ON messages BEGIN\
    \ INSERT INTO messages_text (messages_text, rowid, body) VALUES ('delete', old.id, old.body);\
    \ INSERT INTO messages_text (rowid, body) VALUES (new.id, new.body); END"
  , "CREATE TABLE IF NOT EXISTS reactions (\
    \ reactor TEXT NOT NULL,\
    \ target_author TEXT NOT NULL,\
    \ target_sent_at INTEGER NOT NULL,\
    \ emoji TEXT NOT NULL,\
    \ PRIMARY KEY (reactor, target_author, target_sent_at))"
  , "CREATE TABLE IF NOT EXISTS people (id TEXT PRIMARY KEY, contact_name TEXT, profile_name TEXT)"
  , "CREATE TABLE IF NOT EXISTS groups (id TEXT PRIMARY KEY, name TEXT NOT NULL)"
  , "CREATE TABLE IF NOT EXISTS self (one INTEGER PRIMARY KEY CHECK (one = 1), id TEXT NOT NULL)"
  ]

applyEvents :: Store -> [Event] -> IO ()
applyEvents store events =
  usingStore store $ \conn -> withTransaction conn (mapM_ (applyEvent conn) events)

applyEvent :: Connection -> Event -> IO ()
applyEvent conn = \case
  Posted m ->
    execute
      conn
      "INSERT INTO messages (conversation, author, sent_at, body, attachments, view_once,\
      \ quote_author, quote_sent_at, quote_text, expires_at)\
      \ VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)\
      \ ON CONFLICT (author, sent_at) DO NOTHING"
      ( (messageConversation m, keyAuthor (messageKey m), keySentAt (messageKey m), messageBody m)
          :. (encodeAttachments (messageAttachments m), messageViewOnce m)
          :. (quoteAuthor <$> messageQuote m, quoteSentAt <$> messageQuote m, messageQuote m >>= quoteText)
          :. Only (messageExpiresAt m)
      )
  Edited key body ->
    execute
      conn
      "UPDATE messages SET body = ?, edited = 1 WHERE author = ? AND sent_at = ? AND deleted = 0"
      (body, keyAuthor key, keySentAt key)
  Deleted key -> do
    execute
      conn
      "UPDATE messages SET body = NULL, attachments = '[]', quote_author = NULL, quote_sent_at = NULL,\
      \ quote_text = NULL, deleted = 1 WHERE author = ? AND sent_at = ?"
      (keyAuthor key, keySentAt key)
    execute conn "DELETE FROM reactions WHERE target_author = ? AND target_sent_at = ?" (keyAuthor key, keySentAt key)
  Reacted reactor key emoji ->
    execute
      conn
      "INSERT INTO reactions (reactor, target_author, target_sent_at, emoji) VALUES (?, ?, ?, ?)\
      \ ON CONFLICT (reactor, target_author, target_sent_at) DO UPDATE SET emoji = excluded.emoji"
      (reactor, keyAuthor key, keySentAt key, emoji)
  Unreacted reactor key ->
    execute
      conn
      "DELETE FROM reactions WHERE reactor = ? AND target_author = ? AND target_sent_at = ?"
      (reactor, keyAuthor key, keySentAt key)
  PersonNamed sid name ->
    execute
      conn
      "INSERT INTO people (id, profile_name) VALUES (?, ?)\
      \ ON CONFLICT (id) DO UPDATE SET profile_name = excluded.profile_name"
      (sid, name)
  ContactNamed sid name ->
    execute
      conn
      "INSERT INTO people (id, contact_name) VALUES (?, ?)\
      \ ON CONFLICT (id) DO UPDATE SET contact_name = excluded.contact_name"
      (sid, name)
  GroupNamed gid name ->
    execute
      conn
      "INSERT INTO groups (id, name) VALUES (?, ?) ON CONFLICT (id) DO UPDATE SET name = excluded.name"
      (groupIdText gid, name)

encodeAttachments :: [Attachment] -> Text
encodeAttachments = TE.decodeUtf8 . LBS.toStrict . Aeson.encode

-- | Records which account the history belongs to, so its own messages
-- read as the owner's.
recordSelf :: Store -> ServiceId -> IO ()
recordSelf store self =
  usingStore store $ \conn ->
    execute conn "INSERT INTO self (one, id) VALUES (1, ?) ON CONFLICT (one) DO UPDATE SET id = excluded.id" (Only self)

-- | Removes disappearing messages whose time is up, and reactions left
-- pointing at nothing.
purgeExpired :: Store -> Timestamp -> IO ()
purgeExpired store now =
  usingStore store $ \conn -> withTransaction conn $ do
    execute conn "DELETE FROM messages WHERE expires_at <= ?" (Only now)
    execute_
      conn
      "DELETE FROM reactions WHERE NOT EXISTS\
      \ (SELECT 1 FROM messages m WHERE m.author = target_author AND m.sent_at = target_sent_at)"

newtype ResultLimit = ResultLimit Int
  deriving stock (Eq, Show)

parseResultLimit :: Int -> Either Text ResultLimit
parseResultLimit n
  | n >= 1 && n <= 200 = Right (ResultLimit n)
  | otherwise = Left "limit must be between 1 and 200"

defaultResultLimit :: ResultLimit
defaultResultLimit = ResultLimit 30

-- | Words to find, every one of them, anywhere in a message.
newtype SearchText = SearchText [Text]
  deriving stock (Eq, Show)

parseSearchText :: Text -> Either Text SearchText
parseSearchText raw = case T.words raw of
  [] -> Left "query must contain a word to search for"
  terms -> Right (SearchText terms)

-- | Each word becomes an FTS5 string, so no input is read as query syntax.
ftsQuery :: SearchText -> Text
ftsQuery (SearchText terms) = T.unwords (map quote terms)
  where
    quote term = "\"" <> T.replace "\"" "\"\"" term <> "\""

data ConversationSummary = ConversationSummary
  { summaryConversation :: Conversation
  , summaryName :: Maybe Text
  , summaryLastMessageAt :: Timestamp
  , summaryMessages :: Int
  }
  deriving stock (Eq, Show)

-- | Conversations with live messages, most recently active first.
listConversations :: Store -> Timestamp -> ResultLimit -> IO [ConversationSummary]
listConversations store now (ResultLimit limit) =
  usingStore store $ \conn -> do
    rows <-
      query
        conn
        "SELECT m.conversation, MAX(m.sent_at), COUNT(*),\
        \ COALESCE((SELECT COALESCE(p.contact_name, p.profile_name) FROM people p WHERE 'user:' || p.id = m.conversation),\
        \          (SELECT g.name FROM groups g WHERE 'group:' || g.id = m.conversation))\
        \ FROM messages m WHERE (m.expires_at IS NULL OR m.expires_at > ?)\
        \ GROUP BY m.conversation ORDER BY MAX(m.sent_at) DESC, m.conversation LIMIT ?"
        (now, limit)
    pure [ConversationSummary conversation name lastAt count | (conversation, lastAt, count, name) <- rows]

data ReactionView = ReactionView
  { reactionBy :: ServiceId
  , reactionByName :: Maybe Text
  , reactionViewEmoji :: Text
  }
  deriving stock (Eq, Show)

data MessageView = MessageView
  { viewConversation :: Conversation
  , viewKey :: MessageKey
  , viewAuthorName :: Maybe Text
  , viewFromSelf :: Bool
  , viewBody :: Maybe Text
  , viewAttachments :: [Attachment]
  , viewViewOnce :: Bool
  , viewQuote :: Maybe Quote
  , viewEdited :: Bool
  , viewDeleted :: Bool
  , viewReactions :: [ReactionView]
  }
  deriving stock (Eq, Show)

messageColumns :: Query
messageColumns =
  "SELECT m.conversation, m.author, m.sent_at,\
  \ (SELECT COALESCE(p.contact_name, p.profile_name) FROM people p WHERE p.id = m.author),\
  \ COALESCE(m.author = (SELECT s.id FROM self s), 0),\
  \ m.body, m.attachments, m.view_once, m.quote_author, m.quote_sent_at, m.quote_text, m.edited, m.deleted\
  \ FROM messages m"

type MessageRow =
  (Conversation, ServiceId, Timestamp, Maybe Text, Bool)
    :. (Maybe Text, Text, Bool, Maybe ServiceId, Maybe Timestamp, Maybe Text, Bool, Bool)

messageViews :: Connection -> [MessageRow] -> IO [MessageView]
messageViews conn rows =
  forM rows $ \((conversation, author, sentAt, authorName, fromSelf) :. (body, attachments, viewOnce, qAuthor, qSentAt, qText, edited, deleted)) -> do
    decoded <- either (throwIO . userError . ("stored attachments unreadable: " <>)) pure (Aeson.eitherDecodeStrict (TE.encodeUtf8 attachments))
    reactions <-
      query
        conn
        "SELECT r.reactor, (SELECT COALESCE(p.contact_name, p.profile_name) FROM people p WHERE p.id = r.reactor), r.emoji\
        \ FROM reactions r WHERE r.target_author = ? AND r.target_sent_at = ? ORDER BY r.reactor"
        (author, sentAt)
    pure
      MessageView
        { viewConversation = conversation
        , viewKey = MessageKey author sentAt
        , viewAuthorName = authorName
        , viewFromSelf = fromSelf
        , viewBody = body
        , viewAttachments = decoded
        , viewViewOnce = viewOnce
        , viewQuote = Quote <$> qAuthor <*> qSentAt <*> pure qText
        , viewEdited = edited
        , viewDeleted = deleted
        , viewReactions = [ReactionView by name emoji | (by, name, emoji) <- reactions]
        }

-- | One conversation's live messages sent before a time, newest first.
readConversation :: Store -> Timestamp -> Conversation -> Maybe Timestamp -> ResultLimit -> IO [MessageView]
readConversation store now conversation before (ResultLimit limit) =
  usingStore store $ \conn ->
    query
      conn
      (messageColumns <> " WHERE m.conversation = ? AND (m.expires_at IS NULL OR m.expires_at > ?)\
                         \ AND (? IS NULL OR m.sent_at < ?) ORDER BY m.sent_at DESC, m.author LIMIT ?")
      (conversation, now, before, before, limit)
      >>= messageViews conn

-- | Live messages containing every word, newest first.
searchMessages :: Store -> Timestamp -> SearchText -> Maybe Conversation -> ResultLimit -> IO [MessageView]
searchMessages store now terms conversation (ResultLimit limit) =
  usingStore store $ \conn ->
    query
      conn
      (messageColumns <> " JOIN messages_text t ON t.rowid = m.id\
                         \ WHERE messages_text MATCH ? AND (m.expires_at IS NULL OR m.expires_at > ?)\
                         \ AND (? IS NULL OR m.conversation = ?) ORDER BY m.sent_at DESC, m.author LIMIT ?")
      (ftsQuery terms, now, conversation, conversation, limit)
      >>= messageViews conn

-- | People and groups whose name contains the text, as conversations a
-- message can be sent to.
findNames :: Store -> Text -> IO [(Conversation, Text)]
findNames store needle =
  usingStore store $ \conn -> do
    people <-
      query
        conn
        "SELECT id, COALESCE(contact_name, profile_name) FROM people\
        \ WHERE COALESCE(contact_name, profile_name) LIKE '%' || ? || '%' ORDER BY 2"
        (Only needle)
    groups <- query conn "SELECT id, name FROM groups WHERE name LIKE '%' || ? || '%' ORDER BY name" (Only needle)
    groupRows <- forM groups $ \(gid, name) -> either (throwIO . userError . T.unpack) (\g -> pure (Group g, name)) (parseGroupId gid)
    pure ([(Direct sid, name) | (sid, name) <- people] <> groupRows)

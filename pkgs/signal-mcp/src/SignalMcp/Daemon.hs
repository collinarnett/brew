-- | A JSON-RPC client for signal-cli's daemon socket. The daemon owns the
-- account; everything here asks it to act and never touches its files.
module SignalMcp.Daemon
  ( Account
  , accountText
  , parseAccount
  , Connection
  , DaemonError (..)
  , withDaemon
  , call
  , Identity (..)
  , resolveIdentity
  , subscribe
  , Contact (..)
  , listContacts
  , listGroups
  , SendTarget (..)
  , sendMessage
  , disappearingTimer
  ) where

import Control.Exception (Exception, bracket, catch, throwIO)
import Control.Monad (unless)
import Data.Aeson (FromJSON, Value (..), object, withObject, (.!=), (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Types (Pair, parseEither)
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as LBS
import Data.Char (isDigit)
import Data.Int (Int64)
import Data.IORef (IORef, atomicModifyIORef', newIORef)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import Network.Socket qualified as Socket
import System.IO (BufferMode (..), Handle, IOMode (..), hClose, hFlush, hSetBuffering)
import System.Timeout (timeout)

import SignalMcp.Conversation

-- | The registered phone number signal-cli knows the account by.
newtype Account = Account Text
  deriving stock (Eq, Show)

accountText :: Account -> Text
accountText (Account number) = number

parseAccount :: Text -> Either Text Account
parseAccount raw = case T.stripPrefix "+" raw of
  Just digits | not (T.null digits), T.all isDigit digits -> Right (Account raw)
  _ -> Left ("not a +E.164 account number: " <> raw)

data Connection = Connection
  { connHandle :: Handle
  , connNextId :: IORef Int
  }

data DaemonError
  = DaemonUnreachable FilePath String
  | DaemonRefused Text Text
  | DaemonTimedOut Text
  | DaemonUnexpected Text String
  | NoAccount
  | SeveralAccounts [Text]
  deriving stock (Show)

instance Exception DaemonError

withDaemon :: FilePath -> (Connection -> IO a) -> IO a
withDaemon socketPath action =
  bracket connect hClose $ \handle -> do
    hSetBuffering handle LineBuffering
    counter <- newIORef 0
    action (Connection handle counter)
  where
    connect = do
      sock <- Socket.socket Socket.AF_UNIX Socket.Stream Socket.defaultProtocol
      Socket.connect sock (Socket.SockAddrUnix socketPath)
        `onIOError` \err -> Socket.close sock >> throwIO (DaemonUnreachable socketPath (show err))
      Socket.socketToHandle sock ReadWriteMode
    onIOError :: IO a -> (IOError -> IO a) -> IO a
    onIOError = catch

-- | Calls one method and returns its result. Messages arriving on the
-- connection meanwhile are dropped, so a subscribed connection is not
-- used for calls.
call :: Connection -> Text -> [Pair] -> IO Value
call conn method params = do
  requestId <- atomicModifyIORef' (connNextId conn) (\n -> (n + 1, n))
  BC.hPutStrLn (connHandle conn) . LBS.toStrict . Aeson.encode $
    object ["jsonrpc" .= ("2.0" :: Text), "id" .= requestId, "method" .= method, "params" .= object params]
  hFlush (connHandle conn)
  -- Sending reaches Signal's servers and every recipient device.
  timeout (30 * 1000000) (awaitResponse requestId) >>= maybe (throwIO (DaemonTimedOut method)) pure
  where
    awaitResponse requestId = do
      line <- BC.hGetLine (connHandle conn)
      reply <- either (throwIO . DaemonUnexpected method) pure (Aeson.eitherDecodeStrict line)
      case parseEither (withObject "reply" (\o -> (,,) <$> o .:? "id" <*> o .:? "result" <*> o .:? "error")) reply of
        Right (Just replyId, result, failure)
          | replyId == requestId -> case (result, failure) of
              (_, Just err) -> throwIO (DaemonRefused method (errorMessage err))
              (Just value, Nothing) -> pure value
              (Nothing, Nothing) -> pure Null
        _ -> awaitResponse requestId
    errorMessage err = either (const (T.pack (show err))) id (parseEither (withObject "error" (.: "message")) err)

decodeResult :: FromJSON a => Text -> Value -> IO a
decodeResult method value = either (throwIO . DaemonUnexpected method) pure (parseEither Aeson.parseJSON value)

data Identity = Identity
  { identityAccount :: Account
  , identitySelf :: ServiceId
  }
  deriving stock (Eq, Show)

-- | The account to act as, and its own Signal id. With no account
-- configured the daemon must hold exactly one.
resolveIdentity :: Connection -> Maybe Account -> IO Identity
resolveIdentity conn configured = do
  account <- maybe discover pure configured
  contacts <- call conn "listContacts" ["account" .= accountText account, "recipient" .= [accountText account], "allRecipients" .= True]
  selves <- decodeResult "listContacts" contacts >>= traverse (contactP "listContacts")
  case [sid | Contact sid _ _ <- selves] of
    self : _ -> pure (Identity account self)
    [] -> throwIO (DaemonUnexpected "listContacts" "the account has no Signal id of its own")
  where
    discover = do
      accounts <- call conn "listAccounts" [] >>= decodeResult "listAccounts"
      numbers <- traverse (either (throwIO . DaemonUnexpected "listAccounts" . T.unpack) pure . parseAccount) =<< traverse (\o -> either (throwIO . DaemonUnexpected "listAccounts") pure (parseEither (.: "number") o)) accounts
      case numbers of
        [account] -> pure account
        [] -> throwIO NoAccount
        several -> throwIO (SeveralAccounts (map accountText several))

-- | Starts delivery of received messages on this connection and hands each
-- envelope to the callback, until the daemon closes the connection.
subscribe :: Connection -> Account -> (Value -> IO ()) -> IO ()
subscribe conn account onEnvelope = do
  _ <- call conn "subscribeReceive" ["account" .= accountText account]
  let loop = do
        line <- BC.hGetLine (connHandle conn)
        unless (BC.null line) $
          case Aeson.eitherDecodeStrict line >>= parseEither receivedEnvelope of
            Right (Just envelope) -> onEnvelope envelope
            Right Nothing -> pure ()
            Left err -> throwIO (DaemonUnexpected "receive" err)
        loop
  loop
  where
    receivedEnvelope = withObject "notification" $ \o ->
      o .:? "method" >>= \case
        Just ("receive" :: Text) -> do
          params <- o .: "params"
          result <- params .: "result"
          Just <$> result .: "envelope"
        _ -> pure Nothing

data Contact = Contact
  { contactId :: ServiceId
  , contactSavedName :: Maybe Text
  , contactProfileName :: Maybe Text
  }
  deriving stock (Eq, Show)

contactP :: Text -> Value -> IO Contact
contactP method = either (throwIO . DaemonUnexpected method) pure . parseEither parser
  where
    parser = withObject "contact" $ \o -> do
      uuid <- o .:? "uuid"
      number <- o .:? "number"
      sid <- case catMaybes [uuid >>= nonEmpty, number >>= nonEmpty] of
        raw : _ -> either (fail . T.unpack) pure (parseServiceId raw)
        [] -> fail "contact has neither uuid nor number"
      nick <- o .:? "nickName"
      name <- o .:? "name"
      profile <- o .:? "profile"
      given <- maybe (pure Nothing) (.:? "givenName") profile
      family <- maybe (pure Nothing) (.:? "familyName") profile
      let profileName = nonEmpty (T.unwords (catMaybes [given >>= nonEmpty, family >>= nonEmpty]))
      pure (Contact sid (firstNonEmpty [nick, name]) profileName)
    firstNonEmpty = \case
      [] -> Nothing
      x : rest -> maybe (firstNonEmpty rest) Just (x >>= nonEmpty)
    nonEmpty t = if T.null (T.strip t) then Nothing else Just (T.strip t)

listContacts :: Connection -> Account -> IO [Contact]
listContacts conn account =
  call conn "listContacts" ["account" .= accountText account]
    >>= decodeResult "listContacts"
    >>= traverse (contactP "listContacts")

listGroups :: Connection -> Account -> IO [(GroupId, Text)]
listGroups conn account = do
  groups <- call conn "listGroups" ["account" .= accountText account] >>= decodeResult "listGroups"
  catMaybes <$> traverse group groups
  where
    group :: Value -> IO (Maybe (GroupId, Text))
    group = either (throwIO . DaemonUnexpected "listGroups") pure . parseEither (withObject "group" groupP)
    groupP o = do
      gid <- o .: "id" >>= either (fail . T.unpack) pure . parseGroupId
      name <- o .:? "name"
      pure (case name of
        Just n | not (T.null n) -> Just (gid, n)
        _ -> Nothing)

data SendTarget
  = ToPerson ServiceId
  | ToGroup GroupId
  deriving stock (Eq, Show)

-- | Sends a text message and returns the timestamp Signal identifies it by.
-- Fails unless at least one recipient device accepted it.
sendMessage :: Connection -> Account -> SendTarget -> Text -> IO Timestamp
sendMessage conn account target body = do
  result <- call conn "send" (["account" .= accountText account, "message" .= body] <> targetParams)
  (sentAt, outcomes) <-
    either (throwIO . DaemonUnexpected "send") pure $
      parseEither (withObject "send result" (\o -> (,) <$> o .: "timestamp" <*> o .:? "results" .!= [])) result
  let failures = [outcome | outcome <- outcomes, outcomeType outcome /= Just "SUCCESS"]
  if not (null failures) && length failures == length outcomes
    then throwIO (DaemonRefused "send" ("no recipient accepted the message: " <> T.pack (show (map outcomeType failures))))
    else pure (Timestamp sentAt)
  where
    targetParams = case target of
      ToPerson sid -> ["recipient" .= [serviceIdText sid]]
      ToGroup gid -> ["groupId" .= groupIdText gid]
    outcomeType :: Value -> Maybe Text
    outcomeType = either (const Nothing) id . parseEither (withObject "outcome" (.:? "type"))

-- | The disappearing-message timer the conversation is set to, in seconds;
-- 0 when messages stay.
disappearingTimer :: Connection -> Account -> SendTarget -> IO Int64
disappearingTimer conn account target = do
  entries <- case target of
    ToPerson sid -> call conn "listContacts" ["account" .= accountText account, "recipient" .= [serviceIdText sid], "allRecipients" .= True] >>= decodeResult "listContacts"
    ToGroup gid -> call conn "listGroups" ["account" .= accountText account, "groupId" .= [groupIdText gid]] >>= decodeResult "listGroups"
  timers <- traverse (either (throwIO . DaemonUnexpected "disappearing timer") pure . parseEither (withObject "entry" (.: "messageExpirationTime"))) (entries :: [Value])
  pure (case timers of
    timer : _ -> timer
    [] -> 0)

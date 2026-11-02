{-# LANGUAGE MultiWayIf #-}
-- | The adapter to Proton Mail Bridge's IMAP server: STARTTLS against the
-- pinned self-signed certificate, then one short session per operation.
-- Folders open with EXAMINE and fetches use BODY.PEEK, so reading never
-- changes the state of a message.
module ProtonMailMcp.Bridge
  ( listFolders
  , searchSummaries
  , readMessage
  , saveDraft
  , SummaryResult
  ) where

import Control.Exception (onException, throwIO)
import Control.Monad (unless)
import Data.Foldable (traverse_)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.X509 (CertificateChain (..), SignedCertificate)
import Data.X509.Validation (FailedReason (UnknownCA))
import Network.Connection
import Network.HaskellNet.BSStream (BSStream (..))
import Network.HaskellNet.IMAP
  ( AuthType (PLAIN)
  , Flag (Draft, Seen)
  , appendFull
  , examine
  , fetchFlags
  , fetchByStringR
  , list
  , authenticate
  , logout
  )
import Network.HaskellNet.IMAP.Connection (IMAPConnection, newConnection, stream)
import Network.HaskellNet.IMAP.Types (UID)
import Network.TLS qualified as TLS
import System.Timeout (timeout)

import ProtonMailMcp.Config (BridgeEndpoint (..), Config (..))
import ProtonMailMcp.Imap
import ProtonMailMcp.Message (Draft, MessageContent, MessageSummary, matchesHeaders, readContent, renderDraft, summarize)

-- | Bridge answers from a local cache, and it may still be syncing, so this
-- bounds a whole session rather than a single round trip.
sessionTimeoutMicros :: Int
sessionTimeoutMicros = 30 * 1000000

-- | The longest line accepted outside a literal.
maxLineBytes :: Int
maxLineBytes = 1024 * 1024

listFolders :: Config -> IO [Text]
listFolders config = withSession config $ \imap ->
  map (T.pack . snd) <$> list imap

-- | A message whose headers do not parse is reported beside its UID, so one
-- malformed mail cannot hide the rest of a search.
type SummaryResult = Either (UID, Text) MessageSummary

searchSummaries :: Config -> FolderName -> SearchCriteria -> ResultLimit -> IO [SummaryResult]
searchSummaries config folder criteria limit = withSession config $ \imap -> do
  examine imap (renderFolderName folder)
  candidates <- serverSearch (stream imap) criteria
  matches <-
    if needsHeaders criteria
      then decodedMatches (stream imap) criteria candidates
      else pure candidates
  arrivals <- matchingArrivals imap matches
  traverse (fetchSummary imap) (newestArrivals limit arrivals)

serverSearch :: BSStream -> SearchCriteria -> IO [UID]
serverSearch connection criteria = do
  bsPut connection "search "
  traverse_ sendPart (serverSearchCommand criteria)
  bsPut connection "\r\n"
  collect []
  where
    sendPart (Verbatim text) = bsPut connection text
    sendPart (Literal text) = do
      bsPut connection (BC.pack ("{" <> show (BS.length text) <> "}\r\n"))
      requirePrefix "+" =<< bsGetLine connection
      bsPut connection text
    collect uids = do
      line <- bsGetLine connection
      if "search " `BS.isPrefixOf` line
        then uids <$ requirePrefix "search OK" line
        else collect (maybe uids (<> uids) (searchLineUids line))

-- | The candidates whose decoded headers satisfy the criteria, read on the raw
-- stream for the same reason as 'fetchArrivals'.
decodedMatches :: BSStream -> SearchCriteria -> [UID] -> IO [UID]
decodedMatches _ _ [] = pure []
decodedMatches connection criteria candidates = do
  bsPut connection (BC.pack ("headers UID FETCH " <> show (minimum candidates) <> ":" <> show (maximum candidates) <> " (UID BODY.PEEK[HEADER.FIELDS (FROM TO SUBJECT)])\r\n"))
  filter (`Set.member` Set.fromList candidates) <$> collect []
  where
    collect matched = do
      line <- BC.dropWhileEnd (== '\r') <$> bsGetLine connection
      if
        | "headers " `BS.isPrefixOf` line -> matched <$ requirePrefix "headers OK" line
        | Just size <- literalSize line -> do
            block <- bsGet connection size
            trailer <- bsGetLine connection
            case headerBlockUid (line <> trailer) of
              Nothing -> ioError (userError ("unreadable FETCH response: " <> BC.unpack line))
              Just uid -> collect (if matchesHeaders criteria block then uid : matched else matched)
        | otherwise -> collect matched
    literalSize line = do
      (_, sizeText) <- pure (BC.breakEnd (== '{') line)
      fst <$> (BC.unsnoc sizeText >>= \(digits, close) -> if close == '}' then BC.readInt digits else Nothing)

matchingArrivals :: IMAPConnection -> [UID] -> IO [Arrival]
matchingArrivals _ [] = pure []
matchingArrivals imap matches = do
  arrivals <- fetchArrivals (stream imap) (minimum matches) (maximum matches)
  pure (filter ((`Set.member` Set.fromList matches) . arrivalUid) arrivals)

-- | Sent on the raw stream because HaskellNet's response parser takes tens of
-- seconds over the thousands of lines a mailbox answers with.
fetchArrivals :: BSStream -> UID -> UID -> IO [Arrival]
fetchArrivals connection firstUid lastUid = do
  bsPut connection (BC.pack ("arrivals UID FETCH " <> show firstUid <> ":" <> show lastUid <> " (UID INTERNALDATE)\r\n"))
  collect []
  where
    collect arrivals = do
      line <- bsGetLine connection
      if "arrivals " `BS.isPrefixOf` line
        then arrivals <$ requirePrefix "arrivals OK" line
        else case arrivalFromLine line of
          Left err -> ioError (userError (T.unpack err))
          Right found -> collect (maybe arrivals (: arrivals) found)

fetchSummary :: IMAPConnection -> UID -> IO SummaryResult
fetchSummary imap uid = do
  unread <- isUnread imap uid
  header <- fetchSection imap uid "HEADER"
  pure $ case maybe (Left "the server returned no headers") (summarize uid unread) header of
    Left err -> Left (uid, err)
    Right summary -> Right summary

-- | One BODY section of a message, or Nothing when the server sends no such
-- message or section. HaskellNet's own fetches read a missing item as empty.
fetchSection :: IMAPConnection -> UID -> String -> IO (Maybe ByteString)
fetchSection imap uid section = do
  responses <- fetchByStringR imap (uid, uid) ("BODY.PEEK[" <> section <> "]")
  pure $ case responses of
    [(_, items)] -> BC.pack <$> fetchedSection ("BODY[" <> section <> "]") items
    _ -> Nothing

isUnread :: IMAPConnection -> UID -> IO Bool
isUnread imap uid = notElem Seen <$> fetchFlags imap uid

readMessage :: Config -> FolderName -> UID -> IO (Either Text MessageContent)
readMessage config folder uid = withSession config $ \imap -> do
  examine imap (renderFolderName folder)
  fetchSection imap uid "" >>= \case
    Just raw -> do
      unread <- isUnread imap uid
      pure (readContent uid unread raw)
    Nothing -> pure (Left ("no message with uid " <> T.pack (show uid)))

-- | Bridge turns a message appended to Drafts into a Proton draft.
saveDraft :: Config -> Draft -> IO ()
saveDraft config draft = withSession config $ \imap ->
  appendFull imap "Drafts" (renderDraft draft) (Just [Draft]) Nothing

withSession :: Config -> (IMAPConnection -> IO a) -> IO a
withSession config action =
  timeout sessionTimeoutMicros session >>= \case
    Just result -> pure result
    Nothing -> ioError (userError "Proton Bridge did not answer within 30 seconds")
  where
    session = do
      imap <- connectBridge config
      result <- authenticated imap `onException` bsClose (stream imap)
      logout imap
      pure result
    authenticated imap = do
      authenticate imap PLAIN (T.unpack (cfgUsername config)) (T.unpack (cfgPassword config))
      action imap

connectBridge :: Config -> IO IMAPConnection
connectBridge config = do
  context <- initConnectionContext
  connection <-
    connectTo
      context
      ConnectionParams
        { connectionHostname = host
        , connectionPort = endpointImapPort (cfgEndpoint config)
        , connectionUseSecure = Nothing
        , connectionUseSocks = Nothing
        }
  requirePrefix "* OK" =<< connectionGetLine maxLineBytes connection
  connectionPut connection "a0 STARTTLS\r\n"
  requirePrefix "a0 OK" =<< awaitTagged connection
  connectionSetSecure context connection (pinnedTls host (cfgPinnedCertificate config))
  newConnection (connectionStream connection)
  where
    host = endpointHost (cfgEndpoint config)

awaitTagged :: Connection -> IO ByteString
awaitTagged connection = do
  line <- connectionGetLine maxLineBytes connection
  if "* " `BS.isPrefixOf` line then awaitTagged connection else pure line

requirePrefix :: ByteString -> ByteString -> IO ()
requirePrefix expected line =
  unless (expected `BS.isPrefixOf` line) $
    throwIO (userError ("unexpected reply from Proton Bridge: " <> BC.unpack line))

-- | Accepts exactly the configured leaf certificate, by comparing its signed
-- encoding. Bridge's certificate is self-signed, so chain validation has no
-- trust anchor to work from.
pinnedTls :: String -> SignedCertificate -> TLSSettings
pinnedTls host pinned =
  TLSSettings
    defaults
      { TLS.clientHooks =
          (TLS.clientHooks defaults)
            { TLS.onServerCertificate = \_ _ _ (CertificateChain chain) ->
                pure $ case chain of
                  leaf : _ | leaf == pinned -> []
                  _ -> [UnknownCA]
            }
      }
  where
    defaults = TLS.defaultParamsClient host BS.empty

connectionStream :: Connection -> BSStream
connectionStream connection =
  BSStream
    { bsGet = getExactly connection
    , bsPut = connectionPut connection
    , bsFlush = pure ()
    , bsClose = connectionClose connection
    , bsIsOpen = pure True
    , bsGetLine = connectionGetLine maxLineBytes connection
    , bsWaitForInput = connectionWaitForInput connection
    }

getExactly :: Connection -> Int -> IO ByteString
getExactly connection = go BS.empty
  where
    go received 0 = pure received
    go received remaining = do
      chunk <- connectionGet connection remaining
      if BS.null chunk
        then ioError (userError "Proton Bridge closed the connection mid-message")
        else go (received <> chunk) (remaining - BS.length chunk)

-- | Exercises the Bridge adapter against a real dovecot speaking STARTTLS
-- with a self-signed certificate, the same shape of server Bridge is.
module Main (main) where

import Control.Exception (SomeException, bracket, try)
import Control.Monad (forM_, unless)
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.List (isInfixOf, isPrefixOf)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.X509.File (readSignedObject)
import Network.Socket
import System.Directory
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.User (getEffectiveGroupID, getEffectiveUserName, getGroupEntryForID, groupName)
import System.Process
import Test.Tasty
import Test.Tasty.HUnit

import ProtonMailMcp.Bridge
import ProtonMailMcp.Config
import ProtonMailMcp.Imap
import ProtonMailMcp.Message

main :: IO ()
main =
  withSystemTempDirectory "proton-mail-mcp" $ \root ->
    bracket (startDovecot root) (stopDovecot root) $ \config -> do
      otherCertificate <- selfSigned root "other"
      defaultMain (tests root config otherCertificate)

tests :: FilePath -> Config -> FilePath -> TestTree
tests root config otherCertificate =
  testGroup
    "against dovecot"
    [ testCase "folders are listed, including names with spaces" $ do
        folders <- listFolders config
        forM_ ["INBOX", "All Mail", "Drafts"] $ \name ->
          assertBool (show folders) (name `elem` folders)
    , testCase "search returns the newest first with decoded headers" $ do
        found <- successes =<< searchSummaries config inbox emptyCriteria defaultResultLimit
        map summarySubject found @?= [Just "Second", Just "First \8212 with dash"]
    , testCase "newest means arrival time when UIDs run the other way" $ do
        reversed <- folderNamed "Reversed"
        found <- successes =<< searchSummaries config reversed emptyCriteria defaultResultLimit
        map summarySubject found @?= [Just "Newest", Just "Oldest"]
        limited <- successes =<< searchSummaries config reversed emptyCriteria =<< orFail' (parseResultLimit 1)
        map summarySubject limited @?= [Just "Newest"]
    , testCase "a folder with a space in its name can be searched" $ do
        allMail <- folderNamed "All Mail"
        found <- successes =<< searchSummaries config allMail emptyCriteria defaultResultLimit
        map summarySubject found @?= [Just "Archived"]
    , testCase "the criteria filter" $ do
        subject <- searching "Second"
        found <- successes =<< searchSummaries config inbox emptyCriteria {criteriaSubject = Just subject} defaultResultLimit
        map summarySubject found @?= [Just "Second"]
    , testCase "search text cannot widen the search" $ do
        hostile <- searching "nothing\" OR ALL \""
        found <- searchSummaries config inbox emptyCriteria {criteriaSubject = Just hostile} defaultResultLimit
        length found @?= 0
        inBody <- searchSummaries config inbox emptyCriteria {criteriaText = Just hostile} defaultResultLimit
        length inBody @?= 0
    , testCase "encoded subjects are found by accented and plain words" $
        forM_ ["\8212", "dash", "DASH"] $ \word -> do
          wanted <- searching word
          found <- successes =<< searchSummaries config inbox emptyCriteria {criteriaSubject = Just wanted} defaultResultLimit
          map summarySubject found @?= [Just "First \8212 with dash"]
    , testCase "header and body criteria combine" $ do
        subject <- searching "dash"
        body <- searching "first body"
        wrongBody <- searching "second body"
        found <- searchSummaries config inbox emptyCriteria {criteriaSubject = Just subject, criteriaText = Just body} defaultResultLimit
        length found @?= 1
        missed <- searchSummaries config inbox emptyCriteria {criteriaSubject = Just subject, criteriaText = Just wrongBody} defaultResultLimit
        length missed @?= 0
    , testCase "reading and searching leave mail unread" $ do
        initial <- successes =<< searchSummaries config inbox emptyCriteria defaultResultLimit
        let unreadBefore = map summaryUnread initial
        unreadBefore @?= [True, True]
        forM_ initial $ \summary -> do
          content <- readMessage config inbox (summaryUid summary)
          assertBool "read failed" (either (const False) (const True) content)
        afterwards <- successes =<< searchSummaries config inbox emptyCriteria defaultResultLimit
        map summaryUnread afterwards @?= unreadBefore
    , testCase "mail already read is reported as read" $ do
        archive <- folderNamed "Read"
        found <- successes =<< searchSummaries config archive emptyCriteria defaultResultLimit
        map summaryUnread found @?= [False]
    , testCase "a message body arrives intact" $ do
        newest : _ <- successes =<< searchSummaries config inbox emptyCriteria defaultResultLimit
        content <- readMessage config inbox (summaryUid newest) >>= orFail
        contentBody content @?= Right "second body\n"
    , testCase "a message far longer than any line limit is read whole" $ do
        big <- folderNamed "Big"
        found <- successes =<< searchSummaries config big emptyCriteria defaultResultLimit
        uid <- case found of
          [summary] -> pure (summaryUid summary)
          _ -> assertFailure "expected one message"
        content <- readMessage config big uid >>= orFail
        contentBody content @?= Right (T.replicate (maxBodyChars `div` 2) "y\n")
        contentTruncated content @?= True
    , testCase "an unknown uid is an error" $ do
        result <- readMessage config inbox 999999
        assertBool "expected an error" (either (const True) (const False) result)
    , testCase "an unknown folder is an error" $ do
        missing <- folderNamed "No Such Folder"
        result <- try @SomeException (searchSummaries config missing emptyCriteria defaultResultLimit)
        assertBool "expected an error" (either (const True) (const False) result)
    , testCase "a saved draft lands in Drafts, flagged, with clean line endings" $ do
        draft <- orFail (makeDraft "Draft subject" "draft body\nsecond line\n")
        saveDraft config draft
        drafts <- folderNamed "Drafts"
        found <- successes =<< searchSummaries config drafts emptyCriteria defaultResultLimit
        map summarySubject found @?= [Just "Draft subject"]
        stored <- storedMessages (root </> "mail" </> ".Drafts")
        case stored of
          [(fileName, bytes)] -> do
            assertBool ("no draft flag on " <> fileName) ('D' `elem` drop 1 (dropWhile (/= ',') fileName))
            assertBool "stray CR CR LF" (not ("\r\r\n" `BS.isInfixOf` bytes))
          other -> assertFailure ("expected one stored draft, found " <> show (length other))
        content <- readMessage config drafts (uidOf found) >>= orFail
        contentBody content @?= Right "draft body\nsecond line\n"
    , testCase "a certificate other than the pinned one is refused" $ do
        [wrong] <- readSignedObject otherCertificate
        result <- try @SomeException (listFolders config {cfgPinnedCertificate = wrong})
        assertBool "connected past a mismatched pin" (isLeft result)
    , testCase "bad credentials are an error" $ do
        result <- try @SomeException (listFolders config {cfgPassword = "wrong"})
        assertBool "logged in with a bad password" (isLeft result)
    ]
  where
    uidOf found = case found of
      summary : _ -> summaryUid summary
      [] -> 0

-- | Holds braces because HaskellNet's LOGIN escapes them into a command Bridge
-- rejects. dovecot accepts that escaping, so this confirms braces authenticate
-- here but cannot show that LOGIN would fail against Bridge.
testPassword :: Text
testPassword = "se{cr}et"

inbox :: FolderName
inbox = either (error . T.unpack) id (parseFolderName "INBOX")

folderNamed :: Text -> IO FolderName
folderNamed = orFail' . parseFolderName

searching :: Text -> IO SearchText
searching = orFail' . parseSearchText

orFail' :: Either Text a -> IO a
orFail' = either (ioError . userError . T.unpack) pure

orFail :: Either Text a -> IO a
orFail = orFail'

successes :: [SummaryResult] -> IO [MessageSummary]
successes = traverse (either (\(uid, err) -> assertFailure (show uid <> ": " <> T.unpack err)) pure)

makeDraft :: Text -> Text -> Either Text Draft
makeDraft subject draftText = do
  from <- parseSender "tester@example.org"
  recipients <- parseRecipients "friend@example.org"
  case recipients of
    first : rest -> Right (Draft from (first :| rest) [] subject draftText)
    [] -> Left "no recipients"

storedMessages :: FilePath -> IO [(FilePath, BS.ByteString)]
storedMessages folder = do
  names <- concat <$> traverse messagesIn ["new", "cur"]
  traverse (\(path, name) -> (,) name <$> BS.readFile path) names
  where
    messagesIn sub = do
      present <- listDirectory (folder </> sub)
      pure [(folder </> sub </> name, name) | name <- present]

selfSigned :: FilePath -> FilePath -> IO FilePath
selfSigned root name = do
  let certificate = root </> (name <> ".pem")
  callProcess
    "openssl"
    [ "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2", "-subj", "/CN=127.0.0.1"
    , "-keyout", root </> (name <> ".key"), "-out", certificate
    ]
  pure certificate

freePort :: IO PortNumber
freePort = do
  listener <- socket AF_INET Stream defaultProtocol
  bind listener (SockAddrInet 0 (tupleToHostAddress (127, 0, 0, 1)))
  port <- socketPort listener
  close listener
  pure port

message :: String -> String -> String
message subject body =
  "From: sender@example.org\r\nTo: me@example.org\r\nSubject: "
    <> subject
    <> "\r\nDate: Mon, 02 Nov 2026 10:00:00 +0000\r\nMessage-ID: <"
    <> filter (`elem` ['a' .. 'z']) subject
    <> "@example.org>\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n"
    <> body

seedMaildir :: FilePath -> [(String, String)] -> IO ()
seedMaildir folder messages = do
  forM_ ["new", "cur", "tmp"] (createDirectoryIfMissing True . (folder </>))
  forM_ (zip [1 :: Int ..] messages) $ \(index, (subject, body)) ->
    writeFile (folder </> "new" </> (show index <> ".seed")) (message subject body)

startDovecot :: FilePath -> IO Config
startDovecot root = do
  certificatePath <- selfSigned root "server"
  port <- freePort
  user <- getEffectiveUserName
  group <- groupName <$> (getEffectiveGroupID >>= getGroupEntryForID)
  let mail = root </> "mail"
  seedMaildir mail
    [ ("=?UTF-8?B?Rmlyc3Qg4oCUIHdpdGggZGFzaA==?=", "first body\r\n")
    , ("Second", "second body\r\n")
    ]
  seedMaildir (mail </> ".All Mail") [("Archived", "archived\r\n")]
  seedMaildir (mail </> ".Reversed") [("Newest", "new\r\n"), ("Oldest", "old\r\n")]
  setModificationTime (mail </> ".Reversed" </> "new" </> "1.seed") (UTCTime (fromGregorian 2026 1 1) 0)
  setModificationTime (mail </> ".Reversed" </> "new" </> "2.seed") (UTCTime (fromGregorian 2021 1 1) 0)
  seedMaildir (mail </> ".Drafts") []
  seedMaildir (mail </> ".Read") []
  writeFile (mail </> ".Read" </> "cur" </> "1.seed:2,S") (message "Already read" "read\r\n")
  seedMaildir (mail </> ".Big") [("Big", concat (replicate 200000 "y\r\n"))]
  writeFile (root </> "dovecot.conf") $
    unlines
      [ "dovecot_config_version = 2.4.0"
      , "dovecot_storage_version = 2.4.0"
      , "base_dir = " <> root </> "run"
      , "state_dir = " <> root </> "state"
      , "log_path = " <> root </> "dovecot.log"
      , "protocols = imap"
      , "listen = 127.0.0.1"
      , "default_internal_user = " <> user
      , "default_internal_group = " <> group
      , "default_login_user = " <> user
      , "ssl = required"
      , "ssl_server_cert_file = " <> certificatePath
      , "ssl_server_key_file = " <> root </> "server.key"
      , "auth_mechanisms = plain"
      , "passdb static {"
      , "  passdb_static_password = \"{PLAIN}" <> T.unpack testPassword <> "\""
      , "}"
      , "userdb static {"
      , "  fields {"
      , "    uid = " <> user
      , "    gid = " <> group
      , "    home = " <> root </> "home"
      , "  }"
      , "}"
      , "mail_driver = maildir"
      , "mail_path = " <> mail
      , "mail_inbox_path = " <> mail
      , "service imap-login {"
      , "  chroot ="
      , "  inet_listener imap {"
      , "    port = " <> show port
      , "  }"
      , "  inet_listener imaps {"
      , "    port = 0"
      , "  }"
      , "}"
      , "service anvil {"
      , "  chroot ="
      , "}"
      , "service stats {"
      , "  chroot ="
      , "}"
      ]
  createDirectoryIfMissing True (root </> "home")
  callProcess "dovecot" ["-c", root </> "dovecot.conf"]
  awaitListening port (100 :: Int)
  certificates <- readSignedObject certificatePath
  case certificates of
    [certificate] -> do
      sender <- orFail' (parseSender "tester@example.org")
      pure
        Config
          { cfgEndpoint = BridgeEndpoint "127.0.0.1" port
          , cfgUsername = "tester"
          , cfgPassword = testPassword
          , cfgPinnedCertificate = certificate
          , cfgDraftSender = sender
          }
    _ -> ioError (userError "expected exactly one server certificate")

awaitListening :: PortNumber -> Int -> IO ()
awaitListening _ 0 = ioError (userError "dovecot did not start listening")
awaitListening port attempts = do
  probe <- socket AF_INET Stream defaultProtocol
  connected <- try @SomeException (connect probe (SockAddrInet port (tupleToHostAddress (127, 0, 0, 1))))
  close probe
  unless (either (const False) (const True) connected) $ do
    callCommand "sleep 0.05"
    awaitListening port (attempts - 1)

stopDovecot :: FilePath -> Config -> IO ()
stopDovecot root _ = do
  callProcess "dovecot" ["-c", root </> "dovecot.conf", "stop"]
  logged <- readFile (root </> "dovecot.log")
  unless (null (filter isFatal (lines logged))) (putStrLn logged)
  where
    isFatal line = "Fatal" `isInfixOf` line && not ("master" `isPrefixOf` line)

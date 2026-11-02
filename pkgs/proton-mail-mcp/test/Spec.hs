module Main (main) where

import Control.Monad (forM_)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as LBS
import Data.Char (isAscii, isControl)
import Data.List (isInfixOf, sortOn)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (isNothing)
import Data.MIME (Address, Mailbox)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime (..), addUTCTime)
import Data.Time.Calendar (fromGregorian)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.Hedgehog (testProperty)

import ProtonMailMcp (SearchRequest (..), searchRequest)
import ProtonMailMcp.Config (RawConfig (..), parseConfig)
import ProtonMailMcp.Imap
import ProtonMailMcp.Message

main :: IO ()
main =
  defaultMain $
    testGroup
      "proton-mail-mcp"
      [ testGroup "ImapString" imapStringProperties
      , testGroup "search" searchProperties
      , testGroup "headers" headerMatchProperties
  , testGroup "newestArrivals" newestArrivalProperties
      , testGroup "fetchedSection" fetchedSectionProperties
  , testGroup "draft" draftProperties
      , testGroup "reading" readingProperties
      , testGroup "config" configProperties
      ]

unquote :: String -> Maybe String
unquote ('"' : rest) = go rest
  where
    go ['"'] = Just []
    go ('\\' : c : more) | c == '"' || c == '\\' = (c :) <$> go more
    go (c : more) | c /= '"' && c /= '\\' = (c :) <$> go more
    go _ = Nothing
unquote _ = Nothing

anyUnicodeText :: Gen Text
anyUnicodeText = Gen.text (Range.linear 0 40) Gen.unicode

-- | Heavy in exactly the characters that could end a quoted string.
hostileAscii :: Gen Text
hostileAscii =
  Gen.text (Range.linear 0 40) $
    Gen.frequency [(3, Gen.element ['"', '\\', ' ', ')', '(', '{', '}', '*']), (5, Gen.ascii)]

imapStringProperties :: [TestTree]
imapStringProperties =
  [ testProperty "accepted text survives the wire grammar unchanged" . property $ do
      raw <- forAll hostileAscii
      case quoteImapString raw of
        Left _ -> success
        Right quoted -> unquote (renderImapString quoted) === Just (T.unpack raw)
  , testProperty "a folder name is escaped for examine's own quotes" . property $ do
      raw <- forAll (T.filter (not . isControl) <$> hostileAscii)
      case parseFolderName raw of
        Left _ -> T.null raw === True
        Right folder -> unquote ('"' : renderFolderName folder <> "\"") === Just (T.unpack raw)
  , testProperty "rejects exactly control and non-ASCII characters" . property $ do
      raw <- forAll (Gen.choice [hostileAscii, anyUnicodeText])
      let unsafe = T.any (\c -> isControl c || not (isAscii c)) raw
      either (const True) (const False) (quoteImapString raw) === unsafe
  , testProperty "search text refuses only control characters and emptiness" . property $ do
      raw <- forAll anyUnicodeText
      let unusable = T.null raw || T.any isControl raw
      either (const True) (const False) (parseSearchText raw) === unusable
  ]

searchProperties :: [TestTree]
searchProperties =
  [ testProperty "no criteria selects all mail" . property $
      serverSearchCommand emptyCriteria === [Verbatim "UID SEARCH ALL"]
  , testProperty "header criteria never reach the server" . property $ do
      wanted <- forAll anyUnicodeText
      case parseSearchText wanted of
        Left _ -> success
        Right text ->
          serverSearchCommand emptyCriteria {criteriaSubject = Just text, criteriaFrom = Just text, criteriaTo = Just text}
            === serverSearchCommand emptyCriteria
  , testProperty "dates and unread stay server side" . property $
      serverSearchCommand emptyCriteria {criteriaSince = Just (fromGregorian 2026 3 9), criteriaUnreadOnly = True}
        === [Verbatim "UID SEARCH SINCE 09-Mar-2026 UNSEEN"]
  , testProperty "body text travels as a literal, so it cannot end its argument" . property $ do
      request <- evalEither (searchRequest [("text", "x\" OR ALL caf\233")])
      serverSearchCommand (requestCriteria request)
        === [Verbatim "UID SEARCH CHARSET UTF-8 TEXT ", Literal "x\" OR ALL caf\195\169", Verbatim ""]
  , testProperty "reads SEARCH response lines" . property $ do
      searchLineUids "* SEARCH 4 9" === Just [4, 9]
      searchLineUids "* SEARCH" === Just []
      searchLineUids "* 3 EXISTS" === Nothing
  , testProperty "finds the UID on either side of a literal" . property $ do
      headerBlockUid "* 3 FETCH (BODY[HEADER.FIELDS (FROM)] {9} UID 7)" === Just 7
      headerBlockUid "* 3 FETCH (UID 7 BODY[HEADER.FIELDS (FROM)] {9})" === Just 7
  , testProperty "defaults to the newest twenty in INBOX" . property $ do
      request <- evalEither (searchRequest [])
      requestFolder request === either error id (mapLeft' (parseFolderName "INBOX"))
      requestLimit request === defaultResultLimit
  , testProperty "limit outside 1..100 is refused" . property $ do
      n <- forAll (Gen.int (Range.linearFrom 0 (-500) 500))
      let refused = either (const True) (const False) (searchRequest [("limit", T.pack (show n))])
      refused === (n < 1 || n > 100)
  , testProperty "impossible dates are refused" . property $
      either (const True) (const False) (searchRequest [("since", "2026-02-30")]) === True
  ]
  where
    mapLeft' = either (Left . T.unpack) Right

-- | Observed on Proton Bridge: its SEARCH sees raw bytes, so neither a search
-- for an accented name nor one for an ASCII word found an encoded subject.
headerMatchProperties :: [TestTree]
headerMatchProperties =
  [ testProperty "matches inside an encoded subject, accented or not" . property $
      forM_ ["caf\233", "CAF\201", "menu", "MENU"] $ \wanted -> do
        text <- evalEither (parseSearchText wanted)
        assert (matchesHeaders emptyCriteria {criteriaSubject = Just text} encodedBlock)
  , testProperty "text elsewhere does not match the subject" . property $ do
      text <- evalEither (parseSearchText "sender")
      assert (not (matchesHeaders emptyCriteria {criteriaSubject = Just text} encodedBlock))
  , testProperty "every field given must match" . property $ do
      hit <- evalEither (parseSearchText "sender")
      miss <- evalEither (parseSearchText "nobody")
      assert (matchesHeaders emptyCriteria {criteriaFrom = Just hit} encodedBlock)
      assert (not (matchesHeaders emptyCriteria {criteriaFrom = Just hit, criteriaTo = Just miss} encodedBlock))
  , testProperty "a field the message lacks does not match" . property $ do
      text <- evalEither (parseSearchText "x")
      assert (not (matchesHeaders emptyCriteria {criteriaTo = Just text} "Subject: x\r\n\r\n"))
  , testProperty "matching ignores case for any text" . property $ do
      word <- forAll (Gen.text (Range.linear 1 20) Gen.alpha)
      text <- evalEither (parseSearchText (T.toUpper word))
      assert (searchTextMatches text ("..." <> word <> "..."))
  ]
  where
    encodedBlock = "From: Sender <sender@example.org>\r\nSubject: =?UTF-8?B?Q2Fmw6kgbWVudQ==?=\r\n\r\n"

arrival :: Gen Arrival
arrival =
  Arrival
    <$> Gen.word64 (Range.linear 1 100000)
    <*> (flip addUTCTime (UTCTime (fromGregorian 2020 1 1) 0) . fromIntegral <$> Gen.int (Range.linear 0 200000000))

-- | Observed on Proton Bridge: after the initial sync the highest UIDs held
-- the oldest mail, so ordering by UID returned mail from 2021 as the newest.
newestArrivalProperties :: [TestTree]
newestArrivalProperties =
  [ testProperty "matches the sorted reference" . property $ do
      arrivals <- forAll arrivalList
      limit <- forAll limitGen
      newestArrivals (limitOf limit) arrivals
        === map arrivalUid (take limit (sortOn (\a -> Down (arrivalTime a, arrivalUid a)) arrivals))
  , testProperty "time decides the order, whatever the UIDs say" . property $ do
      let older = UTCTime (fromGregorian 2021 1 1) 0
          newer = UTCTime (fromGregorian 2026 1 1) 0
      newestArrivals defaultResultLimit [Arrival 9 older, Arrival 1 newer] === [1, 9]
  , testProperty "input order does not matter" . property $ do
      arrivals <- forAll arrivalList
      shuffled <- forAll (Gen.shuffle arrivals)
      newestArrivals defaultResultLimit arrivals === newestArrivals defaultResultLimit shuffled
  , testProperty "a smaller limit is a prefix of a larger one" . property $ do
      arrivals <- forAll arrivalList
      smaller <- forAll limitGen
      larger <- forAll (Gen.int (Range.linear smaller 100))
      newestArrivals (limitOf smaller) arrivals === take smaller (newestArrivals (limitOf larger) arrivals)
  , testProperty "reads both orderings of a FETCH response" . property $ do
      let expected = Right (Just (Arrival 7 (UTCTime (fromGregorian 2026 3 9) 3600)))
      arrivalFromLine "* 3 FETCH (INTERNALDATE \"09-Mar-2026 02:00:00 +0100\" UID 7)" === expected
      arrivalFromLine "* 3 FETCH (UID 7 INTERNALDATE \" 9-Mar-2026 01:00:00 +0000\")\r" === expected
  , testProperty "other untagged lines are skipped" . property $
      arrivalFromLine "* 12 EXISTS" === Right Nothing
  , testProperty "a FETCH line missing its date is an error" . property $
      either (const True) (const False) (arrivalFromLine "* 3 FETCH (UID 7)") === True
  ]
  where
    arrivalList = Gen.list (Range.linear 0 200) arrival
    limitGen = Gen.int (Range.linear 1 100)
    limitOf = either (error . T.unpack) id . parseResultLimit

-- | Observed on Proton Bridge: HaskellNet found nothing when the section came
-- before UID, so every search result had null headers.
fetchedSectionProperties :: [TestTree]
fetchedSectionProperties =
  [ testProperty "finds the section whether or not UID came first" . property $ do
      value <- forAll (Gen.string (Range.linear 0 40) Gen.ascii)
      fetchedSection "BODY[HEADER]" [("BODY[HEADER]", value), ("UID", "5")] === Just value
      fetchedSection "BODY[HEADER]" [("UID 5 BODY[HEADER]", value)] === Just value
  , testProperty "a response without the section is absent, not empty" . property $ do
      fetchedSection "BODY[]" [("FLAGS", "(\\Seen)"), ("UID", "5")] === Nothing
      fetchedSection "BODY[]" [("BODY[HEADER]", "x")] === Nothing
  ]

draftText :: Gen Text
draftText = Gen.text (Range.linear 1 60) (Gen.frequency [(5, Gen.alphaNum), (2, Gen.element [' ', ':', '"']), (1, Gen.unicode)])

sender :: Mailbox
sender = either (error . T.unpack) id (parseSender "Sender <sender@example.org>")

recipient :: Address
recipient = case parseRecipients "friend@example.org" of
  Right (address : _) -> address
  _ -> error "friend@example.org must parse"

baseDraft :: Draft
baseDraft = Draft sender (recipient :| []) [] "Hello" "Body text\n"

draftProperties :: [TestTree]
draftProperties =
  [ testProperty "subject and body survive rendering and reparsing" . property $ do
      subject <- forAll (T.strip <$> draftText)
      body <- forAll draftText
      content <- evalEither (readContent 1 False (withCrlf (renderDraft baseDraft {draftSubject = subject, draftBody = body})))
      -- purebred-email collapses runs of spaces while unfolding headers.
      fmap (T.unwords . T.words) (summarySubject (contentSummary content)) === Just (T.unwords (T.words subject))
      contentBody content === Right (T.replace "\r\n" "\n" body)
  , testProperty "holds no CR, since append adds line endings itself" . property $ do
      subject <- forAll draftText
      body <- forAll draftText
      assert (BS.notElem 13 (renderDraft baseDraft {draftSubject = subject, draftBody = body}))
  , testProperty "a line break in the subject cannot add a header" . property $ do
      let rendered = renderDraft baseDraft {draftSubject = "hi\r\nBcc: attacker@example.org"}
      let headerBlock = fst (BS.breakSubstring "\n\n" rendered)
      assert (not ("\nBcc:" `BS.isInfixOf` headerBlock))
  , testProperty "cc reaches the headers" . property $ do
      let rendered = BC.unpack (renderDraft baseDraft {draftCc = [recipient]})
      assert ("Cc: friend@example.org" `isInfixOf` rendered)
  , goldenVsString "rendered draft" "test/golden/draft.eml" (pure (LBS.fromStrict (renderDraft baseDraft)))
  , testProperty "recipient lists parse and bad ones are refused" . property $ do
      evalEither (parseRecipients "a@example.org, B <b@example.org>") >>= (=== 2) . length
      either (const True) (const False) (parseRecipients "not an address") === True
  ]

withCrlf :: ByteString -> ByteString
withCrlf = BS.intercalate "\r\n" . BC.split '\n'

fixture :: FilePath -> IO ByteString
fixture name = withCrlf <$> BS.readFile ("test/golden/" <> name)

readFixture :: FilePath -> PropertyT IO MessageContent
readFixture name = do
  raw <- evalIO (fixture name)
  evalEither (readContent 7 True raw)

readingProperties :: [TestTree]
readingProperties =
  [ testProperty "multipart/alternative prefers the plain part" . property $ do
      content <- readFixture "alternative.eml"
      contentBody content === Right "plain version\n"
      map attachmentName (contentAttachments content) === []
  , testProperty "HTML-only mail renders to text without its scripts or styles" . property $ do
      content <- readFixture "html-only.eml"
      body <- evalEither (contentBody content)
      assert ("Visible & decoded" `T.isInfixOf` body)
      assert ("Second line" `T.isInfixOf` body)
      assert (not ("alert" `T.isInfixOf` body))
      assert (not ("color" `T.isInfixOf` body))
  , testProperty "rendered HTML has no indentation or runs of blank lines" . property $ do
      -- Observed on real table-laid-out mail, where text sat among thousands
      -- of characters of tabs and blank lines.
      padding <- forAll (Gen.text (Range.linear 0 30) (Gen.element ['\n', '\t', ' ']))
      let rendered = htmlToText ("<table><tr><td>" <> padding <> "one</td></tr>" <> padding <> "<tr><td>two" <> padding <> "</td></tr></table>")
          kept = T.lines rendered
      assert (all (\line -> line == T.strip line) kept)
      assert (not (T.isInfixOf "\n\n\n" rendered))
      filter (not . T.null) kept === ["one", "two"]
  , testProperty "attachments are listed and their contents withheld" . property $ do
      content <- readFixture "attachment.eml"
      body <- evalEither (contentBody content)
      assert (not ("secret attachment bytes" `T.isInfixOf` body))
      map attachmentName (contentAttachments content) === [Just "notes.txt"]
  , testProperty "encoded headers and base64 bodies decode" . property $ do
      content <- readFixture "encoded.eml"
      summarySubject (contentSummary content) === Just "Caf\233 menu"
      contentBody content === Right "caf\233\n"
  , testProperty "a charset outside the supported set is reported, not garbled" . property $ do
      content <- readFixture "unknown-charset.eml"
      assert (either (const True) (const False) (contentBody content))
  , testProperty "bodies are cut at the bound and say so" . property $ do
      extra <- forAll (Gen.int (Range.linear 0 50))
      let oversized = T.replicate (maxBodyChars + extra) "x"
          raw = withCrlf (renderDraft baseDraft {draftBody = oversized})
      content <- evalEither (readContent 1 False raw)
      fmap T.length (contentBody content) === Right maxBodyChars
      contentTruncated content === (extra > 0)
  , testProperty "unread reflects the caller's flag" . property $ do
      unread <- forAll Gen.bool
      raw <- evalIO (fixture "encoded.eml")
      summary <- evalEither (summarize 1 unread raw)
      summaryUnread summary === unread
  , testProperty "absent headers stay absent" . property $ do
      summary <- evalEither (summarize 1 False "From: a@example.org\r\n\r\n")
      assert (isNothing (summarySubject summary))
      assert (isNothing (summaryDate summary))
  ]

configProperties :: [TestTree]
configProperties =
  [ testProperty "parses the documented file" . property $ do
      raw <- evalEither (parseConfig documented)
      rawImapPort raw === Just 1143
      rawPasswordFile raw === "/run/secrets/bridge"
  , testProperty "a misspelled key is an error, not an ignored setting" . property $
      either (const True) (const False) (parseConfig (documented <> "pasword = \"x\"\n")) === True
  , testProperty "password-file is required" . property $
      either (const True) (const False) (parseConfig (T.replace "password-file" "other" documented)) === True
  ]
  where
    documented =
      "[bridge]\n\
      \username = \"me@example.org\"\n\
      \password-file = \"/run/secrets/bridge\"\n\
      \certificate-file = \"/var/lib/bridge/cert.pem\"\n\
      \draft-from = \"me@example.org\"\n\
      \imap-port = 1143\n"

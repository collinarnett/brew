-- | Pure reading and writing of RFC 5322 messages.
module ProtonMailMcp.Message
  ( MessageSummary (..)
  , summarize
  , MessageContent (..)
  , AttachmentInfo (..)
  , matchesHeaders
  , readContent
  , htmlToText
  , maxBodyChars
  , Draft (..)
  , parseRecipients
  , parseSender
  , renderDraft
  ) where

import Control.Lens (filtered, firstOf, preview, set, to, toListOf, view, (&), _Just, _Right)
import Data.Aeson (ToJSON (..), object, (.=))
import Data.Attoparsec.ByteString (endOfInput, parseOnly)
import Data.ByteString (ByteString)
import Data.CaseInsensitive (CI)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.ByteString.Lazy.Char8 qualified as LC8
import Data.List (group)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NE
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (ZonedTime)
import Data.MIME
import Data.MIME.Charset (charsetText')
import Network.HaskellNet.IMAP.Types (UID)
import ProtonMailMcp.Imap (SearchCriteria (..), searchTextMatches)
import Text.HTML.TagSoup (Tag (..), parseTags, innerText)

data MessageSummary = MessageSummary
  { summaryUid :: UID
  , summaryFrom :: Maybe Text
  , summaryTo :: Maybe Text
  , summarySubject :: Maybe Text
  , summaryDate :: Maybe ZonedTime
  , summaryMessageId :: Maybe Text
  , summaryUnread :: Bool
  }

instance ToJSON MessageSummary where
  toJSON s =
    object
      [ "uid" .= summaryUid s
      , "from" .= summaryFrom s
      , "to" .= summaryTo s
      , "subject" .= summarySubject s
      , "date" .= summaryDate s
      , "message_id" .= summaryMessageId s
      , "unread" .= summaryUnread s
      ]

-- | Summarize a message from its raw header block, or say why it cannot
-- be mail.
summarize :: UID -> Bool -> ByteString -> Either Text MessageSummary
summarize uid unread rawHeader = do
  mail <- parseMessage rawHeader
  pure (summaryOf uid unread mail)

summaryOf :: UID -> Bool -> MIMEMessage -> MessageSummary
summaryOf uid unread mail =
  MessageSummary
    { summaryUid = uid
    , summaryFrom = view (headerText defaultCharsets "From") mail
    , summaryTo = view (headerText defaultCharsets "To") mail
    , summarySubject = view (headerSubject defaultCharsets) mail
    , summaryDate = view headerDate mail
    , summaryMessageId = TE.decodeUtf8Lenient . renderMessageID <$> view headerMessageID mail
    , summaryUnread = unread
    }

parseMessage :: ByteString -> Either Text MIMEMessage
parseMessage raw = case parse (message mime) raw of
  Left err -> Left (T.pack err)
  Right mail -> Right mail

-- | Whether a raw header block satisfies the From, To and Subject criteria,
-- compared after decoding, so encoded headers match like plain ones.
matchesHeaders :: SearchCriteria -> ByteString -> Bool
matchesHeaders criteria rawHeader = case parseMessage rawHeader of
  Left _ -> False
  Right mail ->
    all
      (matchField mail)
      [ ("From", criteriaFrom criteria)
      , ("To", criteriaTo criteria)
      , ("Subject", criteriaSubject criteria)
      ]
  where
    matchField _ (_, Nothing) = True
    matchField mail (headerName, Just wanted) =
      maybe False (searchTextMatches wanted) (view (headerText defaultCharsets headerName) mail)

data AttachmentInfo = AttachmentInfo
  { attachmentName :: Maybe Text
  , attachmentType :: Text
  , attachmentEncodedBytes :: Int
  }

instance ToJSON AttachmentInfo where
  toJSON a =
    object
      [ "name" .= attachmentName a
      , "content_type" .= attachmentType a
      , "encoded_bytes" .= attachmentEncodedBytes a
      ]

data MessageContent = MessageContent
  { contentSummary :: MessageSummary
  , contentCc :: Maybe Text
  , contentBody :: Either Text Text
  , contentTruncated :: Bool
  , contentAttachments :: [AttachmentInfo]
  }

instance ToJSON MessageContent where
  toJSON c =
    object
      [ "message" .= contentSummary c
      , "cc" .= contentCc c
      , "body" .= either (const Nothing) Just (contentBody c)
      , "body_error" .= either Just (const Nothing) (contentBody c)
      , "truncated" .= contentTruncated c
      , "attachments" .= contentAttachments c
      ]

-- | The body returned to the model, bounded so one enormous message cannot
-- fill the conversation.
maxBodyChars :: Int
maxBodyChars = 100000

readContent :: UID -> Bool -> ByteString -> Either Text MessageContent
readContent uid unread raw = do
  mail <- parseMessage raw
  let decodedBody = bodyText mail
  pure
    MessageContent
      { contentSummary = summaryOf uid unread mail
      , contentCc = view (headerText defaultCharsets "Cc") mail
      , contentBody = T.take maxBodyChars <$> decodedBody
      , contentTruncated = either (const False) ((> maxBodyChars) . T.length) decodedBody
      , contentAttachments = toListOf (entities . filtered (not . isBodyPart) . to attachmentInfo) mail
      }

isBodyPart :: WireEntity -> Bool
isBodyPart entity = isInlineText "plain" entity || isInlineText "html" entity

isInlineText :: CI ByteString -> WireEntity -> Bool
isInlineText textSubtype entity =
  not (isAttachment entity) && matchContentType "text" (Just textSubtype) (view contentType entity)

attachmentInfo :: WireEntity -> AttachmentInfo
attachmentInfo entity =
  AttachmentInfo
    { attachmentName = preview (contentDisposition . _Just . filename defaultCharsets) entity
    , attachmentType = showContentType (view contentType entity)
    , attachmentEncodedBytes = maybe 0 BS.length (preview body entity)
    }

-- | The first plain-text part, else the first HTML part rendered to text.
bodyText :: MIMEMessage -> Either Text Text
bodyText mail =
  case (firstPart "plain", firstPart "html") of
    (Just entity, _) -> decodeEntity entity
    (Nothing, Just entity) -> htmlToText <$> decodeEntity entity
    (Nothing, Nothing) -> Left "message has no text part"
  where
    firstPart textSubtype = firstOf (entities . filtered (isInlineText textSubtype)) mail

decodeEntity :: WireEntity -> Either Text Text
decodeEntity entity =
  case preview (transferDecoded' . _Right . charsetText' defaultCharsets) entity of
    Just (Right decoded) -> Right (T.replace "\r\n" "\n" decoded)
    Just (Left err) -> Left (T.pack (show err))
    Nothing -> Left "could not undo the content transfer encoding"

htmlToText :: Text -> Text
htmlToText = tidyLines . innerText . concatMap blockBreak . dropInvisible . parseTags
  where
    blockBreak tag = case tag of
      TagOpen name _ | isLineBreak name -> [TagText "\n"]
      TagClose name | isBlock name -> [TagText "\n"]
      _ -> [tag]
    isLineBreak name = T.toLower name == "br"
    isBlock name = T.toLower name `elem` ["p", "div", "tr", "li", "h1", "h2", "h3", "h4", "h5", "h6"]

-- | Table-laid-out mail renders to far more indentation and blank lines than
-- text, all of which would spend the model's context on nothing.
tidyLines :: Text -> Text
tidyLines = T.strip . T.unlines . squeezeBlanks . map T.strip . T.lines
  where
    squeezeBlanks = concatMap keepOneBlank . group
    keepOneBlank run = if any T.null run then take 1 run else run

dropInvisible :: [Tag Text] -> [Tag Text]
dropInvisible [] = []
dropInvisible (TagOpen name _ : rest)
  | T.toLower name `elem` ["style", "script", "head", "title"] =
      dropInvisible (drop 1 (dropWhile (not . closes name) rest))
  where
    closes open = \case
      TagClose close -> T.toLower close == T.toLower open
      _ -> False
dropInvisible (tag : rest) = tag : dropInvisible rest

data Draft = Draft
  { draftFrom :: Mailbox
  , draftTo :: NonEmpty Address
  , draftCc :: [Address]
  , draftSubject :: Text
  , draftBody :: Text
  }

parseRecipients :: Text -> Either Text [Address]
parseRecipients raw =
  case parseOnly (addressList defaultCharsets <* endOfInput) (TE.encodeUtf8 (T.strip raw)) of
    Left _ -> Left ("not an address list: " <> raw)
    Right addresses -> Right addresses

parseSender :: Text -> Either Text Mailbox
parseSender raw =
  case parseOnly (mailbox defaultCharsets <* endOfInput) (TE.encodeUtf8 (T.strip raw)) of
    Left _ -> Left ("not a mailbox: " <> raw)
    Right sender -> Right sender

-- | The message as LF-terminated bytes. HaskellNet's append terminates each
-- line with CRLF itself, so a CR left here would be sent as stray CR CR LF.
renderDraft :: Draft -> ByteString
renderDraft draft =
  LBS.toStrict . LC8.filter (/= '\r') . renderMessage $
    createTextPlainMessage (draftBody draft)
      & set (headerFrom defaultCharsets) [Single (draftFrom draft)]
      & set (headerTo defaultCharsets) (NE.toList (draftTo draft))
      & set (headerCC defaultCharsets) (draftCc draft)
      & set (headerSubject defaultCharsets) (Just (draftSubject draft))

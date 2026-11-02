-- | What the read and send servers share: argument decoding and turning
-- failures into tool errors.
module SignalMcp.Tool
  ( Arguments
  , tool
  , textProperty
  , integerProperty
  , requiredArgument
  , optionalArgument
  , parseInt
  , run
  , jsonResult
  , currentTime
  , renderTime
  ) where

import Control.Exception (SomeAsyncException, SomeException, fromException, throwIO, try)
import Data.Aeson (ToJSON)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Read qualified as TR
import Data.Time (UTCTime)
import Data.Time.Clock.POSIX (getPOSIXTime, posixSecondsToUTCTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import MCP.Server.Types

import SignalMcp.Conversation (Timestamp (..))

type Arguments = [(ArgumentName, ArgumentValue)]

tool :: Text -> Text -> Text -> [(Text, InputSchemaDefinitionProperty)] -> [Text] -> ToolDefinition
tool name title description schemaProperties schemaRequired =
  ToolDefinition
    { toolDefinitionName = name
    , toolDefinitionDescription = description
    , toolDefinitionInputSchema = InputSchemaDefinitionObject {properties = schemaProperties, required = schemaRequired}
    , toolDefinitionTitle = Just title
    }

textProperty :: Text -> Text -> (Text, InputSchemaDefinitionProperty)
textProperty name description = (name, InputSchemaDefinitionProperty "string" description)

integerProperty :: Text -> Text -> (Text, InputSchemaDefinitionProperty)
integerProperty name description = (name, InputSchemaDefinitionProperty "integer" description)

requiredArgument :: ArgumentName -> (Text -> Either Text a) -> Arguments -> Either Text a
requiredArgument name parse args = maybe (Left (name <> " is required")) parse (lookup name args)

optionalArgument :: ArgumentName -> (Text -> Either Text a) -> Arguments -> Either Text (Maybe a)
optionalArgument name parse args = traverse parse (lookup name args)

parseInt :: Integral a => Text -> Text -> Either Text a
parseInt name raw = case TR.signed TR.decimal raw of
  Right (value, "") -> Right value
  _ -> Left (name <> " must be a whole number, got: " <> raw)

-- | Runs a tool, reporting bad arguments and failures to the caller as
-- tool errors carrying the reason.
run :: Text -> Either Text a -> (a -> IO ToolResult) -> IO (Either Error ToolResult)
run failurePrefix decoded action = case decoded of
  Left err -> pure (Right (toolError err))
  Right request ->
    try (action request) >>= \case
      Right result -> pure (Right result)
      Left err -> case fromException @SomeAsyncException err of
        Just async -> throwIO async
        Nothing -> pure (Right (toolError (failurePrefix <> T.pack (show (err :: SomeException)))))

jsonResult :: ToJSON a => a -> ToolResult
jsonResult = toolText . TE.decodeUtf8Lenient . LBS.toStrict . Aeson.encode

currentTime :: IO Timestamp
currentTime = Timestamp . floor . (* 1000) <$> getPOSIXTime

renderTime :: Timestamp -> Text
renderTime = T.pack . iso8601Show . toUTC
  where
    toUTC :: Timestamp -> UTCTime
    toUTC (Timestamp ms) = posixSecondsToUTCTime (fromIntegral ms / 1000)

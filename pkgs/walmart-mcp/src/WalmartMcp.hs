-- | MCP tools over the walmart library.
--
-- Each call reads the Firefox cookie database fresh, so logging into
-- walmart.com again in the browser takes effect without restarting
-- the server.
module WalmartMcp
  ( listTools
  , callTool
  ) where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (UTCTime, addUTCTime, getCurrentTime, nominalDay)
import MCP.Server.Types
import Text.Read (readMaybe)

import BrowserCookies (CookieError (..), getFirefoxCookies)
import Walmart qualified
import Walmart.Types

listTools :: [ToolDefinition]
listTools =
  [ ToolDefinition
      { toolDefinitionName = "walmart_list_orders"
      , toolDefinitionDescription =
          "List recent Walmart orders as JSON summaries: order id, channel\
          \ (in_store or online), item count, and status."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ( "since"
                , InputSchemaDefinitionProperty
                    { propertyType = "string"
                    , propertyDescription =
                        "Relative time filter like '7 days ago'; units are hours, days, or weeks."
                    }
                )
              , ( "limit"
                , InputSchemaDefinitionProperty
                    { propertyType = "integer"
                    , propertyDescription = "Maximum orders to fetch (default 10)."
                    }
                )
              ]
          , required = []
          }
      , toolDefinitionTitle = Just "List Walmart orders"
      }
  , ToolDefinition
      { toolDefinitionName = "walmart_get_order"
      , toolDefinitionDescription =
          "Fetch one order's full detail as JSON: items with quantities,\
          \ per-item prices in cents, and sales unit types."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ( "order_id"
                , InputSchemaDefinitionProperty
                    { propertyType = "string"
                    , propertyDescription = "Order id, as reported by walmart_list_orders."
                    }
                )
              , ( "channel"
                , InputSchemaDefinitionProperty
                    { propertyType = "string"
                    , propertyDescription =
                        "Where the order was placed: in_store or online, as reported by walmart_list_orders."
                    }
                )
              ]
          , required = [ "order_id", "channel" ]
          }
      , toolDefinitionTitle = Just "Get Walmart order detail"
      }
  ]

callTool :: McpSession IO -> ToolName -> [(ArgumentName, ArgumentValue)] -> IO (Either Error ToolResult)
callTool _session toolName args = case toolName of
  "walmart_list_orders" -> Right <$> listOrders args
  "walmart_get_order"   -> Right <$> getOrder args
  _                     -> pure (Left (UnknownTool toolName))

listOrders :: [(ArgumentName, ArgumentValue)] -> IO ToolResult
listOrders args =
  case parseLimit (lookup "limit" args) of
    Left err -> pure (toolError err)
    Right limit -> do
      sinceResult <- parseSince (lookup "since" args)
      case sinceResult of
        Left err -> pure (toolError err)
        Right mSince ->
          respond =<< withEnv (\env -> Walmart.getOrders env mSince limit)

getOrder :: [(ArgumentName, ArgumentValue)] -> IO ToolResult
getOrder args =
  case (lookup "order_id" args, lookup "channel" args) of
    (Just orderId, Just channelText) ->
      case parseChannel channelText of
        Left err -> pure (toolError err)
        Right channel ->
          respond =<< withEnv (\env -> Walmart.getOrderDetails env (OrderId orderId) channel)
    _ -> pure (toolError "order_id and channel are both required")

-- | Run an API action against a fresh environment built from the
-- current Firefox session.
withEnv :: (Walmart.Env -> IO (Either WalmartError a)) -> IO (Either Text a)
withEnv action = do
  cookieResult <- getFirefoxCookies ".walmart.com"
  case cookieResult of
    Left err -> pure (Left (renderCookieError err))
    Right cookies -> do
      env <- Walmart.newEnv cookies
      result <- action env
      pure $ case result of
        Left err  -> Left (renderWalmartError err)
        Right val -> Right val

respond :: Aeson.ToJSON a => Either Text a -> IO ToolResult
respond (Left err)  = pure (toolError err)
respond (Right val) =
  pure (toolText (TE.decodeUtf8Lenient (LBS.toStrict (Aeson.encode val))))

parseLimit :: Maybe Text -> Either Text Int
parseLimit Nothing = Right 10
parseLimit (Just raw) = case readMaybe (T.unpack raw) of
  Just n  -> Right n
  Nothing -> Left ("limit is not an integer: " <> raw)

parseChannel :: Text -> Either Text OrderChannel
parseChannel "in_store" = Right InStore
parseChannel "online"   = Right Online
parseChannel other      = Left ("channel must be in_store or online, got: " <> other)

parseSince :: Maybe Text -> IO (Either Text (Maybe UTCTime))
parseSince Nothing = pure (Right Nothing)
parseSince (Just input) = do
  now <- getCurrentTime
  pure $ case T.words (T.toLower input) of
    [nStr, unitStr, "ago"] ->
      case readMaybe (T.unpack nStr) :: Maybe Int of
        Nothing -> Left badFormat
        Just n ->
          let unit = T.dropWhileEnd (== 's') unitStr
          in case unit of
            "day"  -> Right (Just (addUTCTime (negate (fromIntegral n * nominalDay)) now))
            "hour" -> Right (Just (addUTCTime (negate (fromIntegral n * 3600)) now))
            "week" -> Right (Just (addUTCTime (negate (fromIntegral n * 7 * nominalDay)) now))
            _otherUnit -> Left ("unknown time unit: " <> unitStr <> "; use day(s), hour(s), or week(s)")
    _otherShape -> Left badFormat
  where
    badFormat = "cannot parse since value '" <> input <> "'; expected e.g. '7 days ago'"

renderCookieError :: CookieError -> Text
renderCookieError (NoProfilesIni path) =
  "No Firefox profiles.ini at " <> T.pack path <> ". Is Firefox set up on this machine?"
renderCookieError (NoDefaultProfile path) =
  "Could not find default Firefox profile in " <> T.pack path
renderCookieError (NoCookiesFound domain path) =
  "No cookies for " <> domain <> " in " <> T.pack path
  <> ". Log into walmart.com in Firefox first."

renderWalmartError :: WalmartError -> Text
renderWalmartError (WalmartNetworkError msg) =
  "Could not reach Walmart: " <> msg
renderWalmartError WalmartBadRequest =
  "Walmart rejected the request (HTTP 400) -- the endpoint hash may have rotated.\
  \ Run walmart-extractor to update endpoints."
renderWalmartError WalmartRateLimited =
  "Rate limited -- log into walmart.com in Firefox to refresh cookies."
renderWalmartError WalmartAccessDenied =
  "Access denied -- cookies expired. Log into walmart.com."
renderWalmartError (WalmartHttpError code) =
  "Walmart API returned HTTP " <> T.pack (show code)
renderWalmartError (WalmartParseError op err) =
  "Failed to parse " <> op <> ": " <> T.pack err
renderWalmartError (WalmartJsonDecodeError err preview) =
  "JSON decode failed: " <> T.pack err <> "\nResponse: " <> unBodyPreview preview

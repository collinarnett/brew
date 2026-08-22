{-# LANGUAGE OverloadedStrings #-}

-- | MCP tools over the walmart library.
--
-- Each call reads the Firefox cookie database fresh, so logging into
-- walmart.com again in the browser takes effect without restarting the
-- server. Every result is an object carrying a @notices@ list, which is
-- where the client reports work it did on its own -- refreshing the
-- endpoint catalog after Walmart retired a hash.
module WalmartMcp
  ( listTools
  , callTool
  ) where

import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
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
import WalmartMcp.Config (Config (..))

listTools :: [ToolDefinition]
listTools =
  [ ToolDefinition
      { toolDefinitionName = "walmart_list_orders"
      , toolDefinitionDescription =
          "List recent Walmart orders as JSON summaries: order id, channel\
          \ (in_store or online), item count, and status."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ("since", prop "string"
                  "Relative time filter like '7 days ago'; units are hours, days, or weeks.")
              , ("limit", prop "integer" "Maximum orders to fetch (default 10).")
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
              [ ("order_id", prop "string" "Order id, as reported by walmart_list_orders.")
              , ("channel", prop "string"
                  "Where the order was placed: in_store or online, as reported by walmart_list_orders.")
              ]
          , required = [ "order_id", "channel" ]
          }
      , toolDefinitionTitle = Just "Get Walmart order detail"
      }
  , ToolDefinition
      { toolDefinitionName = "walmart_search_products"
      , toolDefinitionDescription =
          "Search Walmart's catalogue. Returns products with name, brand,\
          \ description, price in cents, price per unit, stock status, the\
          \ ways the item can be obtained with the soonest date offered,\
          \ and the category path it sits in. Stock is reported against\
          \ one store, named in the result's store field. Alongside the\
          \ products come the categories Walmart offers to narrow the same\
          \ search: pass one of those ids back as category_id to restrict\
          \ results to that department, and searching without one first is\
          \ how you learn the id."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ("query", prop "string" "What to search for, e.g. 'whole milk'.")
              , ("category_id", prop "string"
                  "Restrict to this category, using an id from a previous search's categories list.")
              , ("limit", prop "integer" "Maximum products to return (default 20).")
              , ("page", prop "integer" "Result page, 1-based (default 1).")
              ]
          , required = [ "query" ]
          }
      , toolDefinitionTitle = Just "Search Walmart products"
      }
  , ToolDefinition
      { toolDefinitionName = "walmart_refresh_endpoints"
      , toolDefinitionDescription =
          "Scan Walmart's current frontend build for persisted query hashes\
          \ and update the endpoint catalog. The other tools do this on\
          \ their own when Walmart retires a hash; run it to see what is\
          \ known or to refresh on purpose."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties = [], required = [] }
      , toolDefinitionTitle = Just "Refresh Walmart endpoint catalog"
      }
  ]

prop :: Text -> Text -> InputSchemaDefinitionProperty
prop ty description = InputSchemaDefinitionProperty
  { propertyType = ty
  , propertyDescription = description
  }

callTool :: Config -> McpSession IO -> ToolName -> [(ArgumentName, ArgumentValue)] -> IO (Either Error ToolResult)
callTool config _session toolName args = case toolName of
  "walmart_list_orders"       -> Right <$> listOrders config args
  "walmart_get_order"         -> Right <$> getOrder config args
  "walmart_search_products"   -> Right <$> searchProducts config args
  "walmart_refresh_endpoints" -> Right <$> refreshEndpoints config
  _                           -> pure (Left (UnknownTool toolName))

listOrders :: Config -> [(ArgumentName, ArgumentValue)] -> IO ToolResult
listOrders config args =
  case parseCount 10 (lookup "limit" args) of
    Left err -> pure (toolError err)
    Right limit -> do
      sinceResult <- parseSince (lookup "since" args)
      case sinceResult of
        Left err -> pure (toolError err)
        Right mSince ->
          withEnv config "orders" (\env -> Walmart.getOrders env mSince limit)

getOrder :: Config -> [(ArgumentName, ArgumentValue)] -> IO ToolResult
getOrder config args =
  case (lookup "order_id" args, lookup "channel" args) of
    (Just orderId, Just channelText) ->
      case parseChannel channelText of
        Left err -> pure (toolError err)
        Right channel ->
          withEnv config "order"
            (\env -> Walmart.getOrderDetails env (OrderId orderId) channel)
    _ -> pure (toolError "order_id and channel are both required")

searchProducts :: Config -> [(ArgumentName, ArgumentValue)] -> IO ToolResult
searchProducts config args = case lookup "query" args of
  Nothing -> pure (toolError "query is required")
  Just term -> case (,) <$> parseCount 20 (lookup "limit" args) <*> parseCount 1 (lookup "page" args) of
    Left err -> pure (toolError err)
    Right (limit, page) -> do
      let query = SearchQuery
            { sqTerm       = term
            , sqCategoryId = CategoryId <$> lookup "category_id" args
            , sqPage       = page
            , sqLimit      = limit
            }
      withEnv config "search" (\env -> Walmart.searchProducts env query)

refreshEndpoints :: Config -> IO ToolResult
refreshEndpoints config =
  withEnv config "refreshed" (\env -> fmap (fmap (const True)) (Walmart.refreshCatalog env))

-- | Run an API action against a fresh environment built from the current
-- Firefox session, and report it under @label@ alongside any notices.
withEnv
  :: Aeson.ToJSON a
  => Config -> Text -> (Walmart.Env -> IO (Either WalmartError a)) -> IO ToolResult
withEnv config label action = do
  cookieResult <- getFirefoxCookies ".walmart.com"
  case cookieResult of
    Left err -> pure (toolError (renderCookieError err))
    Right cookies -> do
      catalogPath <- maybe Walmart.defaultCatalogPath pure (cfgCatalogPath config)
      envResult <- Walmart.newEnv cookies catalogPath (cfgSeeds config)
      case envResult of
        Left err -> pure (toolError (renderWalmartError err))
        Right env -> do
          result <- action env
          notices <- Walmart.takeNotices env
          pure $ case result of
            Left err -> toolError (renderWalmartError err <> renderNotices notices)
            Right value -> toolText (encodeText (envelope label value notices))

envelope :: Aeson.ToJSON a => Text -> a -> [Text] -> Aeson.Value
envelope label value notices = Aeson.object
  [ Key.fromText label Aeson..= value
  , "notices" Aeson..= notices
  ]

encodeText :: Aeson.Value -> Text
encodeText = TE.decodeUtf8Lenient . LBS.toStrict . Aeson.encode

renderNotices :: [Text] -> Text
renderNotices [] = ""
renderNotices notices = "\n" <> T.unlines notices

parseCount :: Int -> Maybe Text -> Either Text Int
parseCount fallback Nothing = Right fallback
parseCount _ (Just raw) = case readMaybe (T.unpack raw) of
  Just n | n > 0 -> Right n
  Just n         -> Left ("expected a positive number, got: " <> T.pack (show n))
  Nothing        -> Left ("not an integer: " <> raw)

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
renderWalmartError (WalmartBadRequest preview) =
  "Walmart rejected the request (HTTP 400): " <> unBodyPreview preview
renderWalmartError WalmartRateLimited =
  "Rate limited -- log into walmart.com in Firefox to refresh cookies."
renderWalmartError WalmartAccessDenied =
  "Access denied -- cookies expired. Log into walmart.com."
renderWalmartError (WalmartHttpError 412 preview)
  | "PX" `T.isInfixOf` unBodyPreview preview =
      "Walmart's bot protection (PerimeterX) refused the request. It clears\
      \ on its own; loading walmart.com in Firefox and waiting before\
      \ retrying is what recovers the session. Response: "
      <> unBodyPreview preview
renderWalmartError (WalmartHttpError code preview) =
  "Walmart API returned HTTP " <> T.pack (show code) <> ": " <> unBodyPreview preview
renderWalmartError (WalmartParseError op err) =
  "Failed to parse " <> op <> ": " <> T.pack err
renderWalmartError (WalmartJsonDecodeError err preview) =
  "JSON decode failed: " <> T.pack err <> "\nResponse: " <> unBodyPreview preview
renderWalmartError (WalmartOperationUnresolved name) =
  "No endpoint hash known for " <> unOperationName name
  <> ", and discovery did not find one. Operations Walmart does not ship in\
     \ its frontend bundles must be supplied by an [[operation]] entry in\
     \ the walmart-mcp config."
renderWalmartError (WalmartStaleAfterRefresh name preview) =
  "Walmart still rejected " <> unOperationName name
  <> " after the endpoint catalog was refreshed, so a stale hash is not the\
     \ cause. Response: " <> unBodyPreview preview
renderWalmartError (WalmartDiscoveryFailed msg) =
  "Endpoint discovery failed: " <> msg

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
          \ description, offer id (what walmart_update_cart takes), price in cents, price per unit, stock status, the\
          \ ways the item can be obtained with the soonest date offered,\
          \ and the category path it sits in. Stock is reported against\
          \ one store, named in the result's store field: the store the cart is\
          \ assorted against, which walmart_set_store changes. Alongside the\
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
      { toolDefinitionName = "walmart_get_product"
      , toolDefinitionDescription =
          "Read one product's page: name, brand, UPC barcode, price, the\
          \ ingredient statement, the package net content (e.g. '1 GAL',\
          \ '1 lb'), the category path, and the full specification table.\
          \ The UPC is what nutrition databases are keyed by, and the net\
          \ content is the purchase unit for stocking. This renders the\
          \ page in a browser, so it takes several seconds per item; call\
          \ it per item you mean to stock, never per search result."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ("us_item_id", prop "string" "Item id, as reported by walmart_search_products or a cart line.") ]
          , required = [ "us_item_id" ]
          }
      , toolDefinitionTitle = Just "Get Walmart product"
      }
  , ToolDefinition
      { toolDefinitionName = "walmart_find_stores"
      , toolDefinitionDescription =
          "List Walmart stores around a postal code, nearest first: store\
          \ id, name, city, distance in miles, and how each hands over an\
          \ order (delivery, pickup_in_store, pickup_curbside). Store ids\
          \ are what the cart and the slot listing report, so this is how\
          \ to learn which store a stock answer was about."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ("postal_code", prop "string" "Postal code to search around.")
              , ("radius_miles", prop "integer" "Search radius in miles (default 20).")
              ]
          , required = [ "postal_code" ]
          }
      , toolDefinitionTitle = Just "Find Walmart stores"
      }
  , ToolDefinition
      { toolDefinitionName = "walmart_get_cart"
      , toolDefinitionDescription =
          "Report the session's cart: its id, the store it is assorted\
          \ against, whether that store was chosen explicitly or inferred\
          \ by Walmart, the fulfillment intent, and how many lines it holds."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties = [], required = [] }
      , toolDefinitionTitle = Just "Get Walmart cart"
      }
  , ToolDefinition
      { toolDefinitionName = "walmart_update_cart"
      , toolDefinitionDescription =
          "Set one offer's quantity in the cart and return what the cart now\
          \ holds: each line's item id, offer id, quantity and price, plus\
          \ the subtotal. A quantity of zero removes the line.\
          \ The offer id comes from walmart_search_products or from a cart\
          \ line; the cart id from walmart_get_cart. This changes the\
          \ shopper's real cart."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ("cart_id", prop "string" "Cart id, as reported by walmart_get_cart.")
              , ("offer_id", prop "string" "Offer id of the item, as reported by walmart_search_products.")
              , ("quantity", prop "integer" "Quantity to set; 0 removes the line.")
              ]
          , required = [ "cart_id", "offer_id", "quantity" ]
          }
      , toolDefinitionTitle = Just "Update Walmart cart"
      }
  , ToolDefinition
      { toolDefinitionName = "walmart_list_slots"
      , toolDefinitionDescription =
          "List the delivery or pickup slots Walmart offers the cart, by\
          \ day. Each slot has an id, a timing (a scheduled window or an\
          \ express promise in minutes), availability, the fee in cents,\
          \ when the offer expires, and the slot_metadata Walmart expects\
          \ back when the slot is reserved."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ("fulfillment", prop "string" "delivery or pickup (default delivery).") ]
          , required = []
          }
      , toolDefinitionTitle = Just "List Walmart slots"
      }
  , ToolDefinition
      { toolDefinitionName = "walmart_reserve_slot"
      , toolDefinitionDescription =
          "Hold a delivery or pickup slot for the cart. Pass the\
          \ slot_metadata of a slot from walmart_list_slots. Returns the\
          \ reservation: its id, the slot window and fee, and the deadline\
          \ Walmart holds it until -- the order must be placed in the\
          \ browser before then. This changes the shopper's real cart."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ("cart_id", prop "string" "Cart id, as reported by walmart_get_cart.")
              , ("slot_metadata", prop "string" "The slot_metadata of the chosen slot, verbatim from walmart_list_slots.")
              ]
          , required = [ "cart_id", "slot_metadata" ]
          }
      , toolDefinitionTitle = Just "Reserve Walmart slot"
      }
  , ToolDefinition
      { toolDefinitionName = "walmart_cancel_reservation"
      , toolDefinitionDescription =
          "Release a held slot and return the cart as it stands."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ("reservation_id", prop "string" "Reservation id, as reported by walmart_reserve_slot or walmart_get_cart.") ]
          , required = [ "reservation_id" ]
          }
      , toolDefinitionTitle = Just "Cancel Walmart reservation"
      }
  , ToolDefinition
      { toolDefinitionName = "walmart_set_store"
      , toolDefinitionDescription =
          "Point the cart, and with it every stock answer from\
          \ walmart_search_products, at a store from walmart_find_stores.\
          \ Walmart drops any held slot when the store changes. This\
          \ changes the shopper's real session: set it back when a\
          \ comparison is done."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ("cart_id", prop "string" "Cart id, as reported by walmart_get_cart.")
              , ("store_id", prop "string" "Store id, as reported by walmart_find_stores.")
              ]
          , required = [ "cart_id", "store_id" ]
          }
      , toolDefinitionTitle = Just "Set Walmart store"
      }
  , ToolDefinition
      { toolDefinitionName = "walmart_compare_stores"
      , toolDefinitionDescription =
          "Run the same searches against several stores and report, per\
          \ store, which queries have an in-stock result and the best\
          \ match for each. Points the cart at each store in turn and\
          \ restores the one it started on; if restoring fails the result\
          \ says so and the cart is left on the last store. Costs one\
          \ request per store plus one per store per query, so keep the\
          \ lists short."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ("cart_id", prop "string" "Cart id, as reported by walmart_get_cart.")
              , ("store_ids", prop "string" "Comma-separated store ids from walmart_find_stores.")
              , ("queries", prop "string" "Search terms separated by | (vertical bar), one per ingredient.")
              , ("category_id", prop "string" "Restrict every search to this category, e.g. the Food department id.")
              ]
          , required = [ "cart_id", "store_ids", "queries" ]
          }
      , toolDefinitionTitle = Just "Compare Walmart stores"
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
  "walmart_get_product"       -> Right <$> getProduct config args
  "walmart_find_stores"       -> Right <$> findStores config args
  "walmart_get_cart"          -> Right <$> getCart config
  "walmart_list_slots"        -> Right <$> listSlots config args
  "walmart_update_cart"       -> Right <$> updateCart config args
  "walmart_reserve_slot"      -> Right <$> reserveSlot config args
  "walmart_cancel_reservation" -> Right <$> cancelReservation config args
  "walmart_set_store"         -> Right <$> setStore config args
  "walmart_compare_stores"    -> Right <$> compareStores config args
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

getProduct :: Config -> [(ArgumentName, ArgumentValue)] -> IO ToolResult
getProduct config args = case (lookup "us_item_id" args, cfgRenderer config) of
  (Nothing, _) -> pure (toolError "us_item_id is required")
  (_, Nothing) -> pure (toolError
    "No page renderer is configured: set renderer.lightpanda in the walmart-mcp config to the lightpanda executable.")
  (Just item, Just renderer) -> do
    result <- Walmart.getProduct renderer (UsItemId item)
    pure $ case result of
      Left err -> toolError (renderWalmartError err)
      Right detail -> toolText (encodeText (envelope "product" detail []))

findStores :: Config -> [(ArgumentName, ArgumentValue)] -> IO ToolResult
findStores config args = case lookup "postal_code" args of
  Nothing -> pure (toolError "postal_code is required")
  Just postal -> case parseCount 20 (lookup "radius_miles" args) of
    Left err -> pure (toolError err)
    Right radius ->
      withEnv config "stores" (\env -> Walmart.findStores env StoreSearch
        { ssPostalCode = PostalCode postal, ssRadiusMiles = radius })

getCart :: Config -> IO ToolResult
getCart config = withEnv config "cart" Walmart.getCart

updateCart :: Config -> [(ArgumentName, ArgumentValue)] -> IO ToolResult
updateCart config args =
  case (lookup "cart_id" args, lookup "offer_id" args, lookup "quantity" args) of
    (Just cid, Just offer, Just rawQty) -> case readMaybe (T.unpack rawQty) of
      Just qty | qty >= 0 ->
        withEnv config "receipt" (\env -> Walmart.updateCart env (CartId cid)
          [ CartUpdate { cuOfferId = OfferId offer, cuQuantity = qty } ])
      _notAQuantity -> pure (toolError ("quantity must be a whole number of at least 0, got: " <> rawQty))
    _ -> pure (toolError "cart_id, offer_id and quantity are all required")

reserveSlot :: Config -> [(ArgumentName, ArgumentValue)] -> IO ToolResult
reserveSlot config args = case (lookup "cart_id" args, lookup "slot_metadata" args) of
  (Just cid, Just metadata) ->
    withEnv config "reservation" (\env -> Walmart.reserveSlot env (CartId cid) (SlotMetadata metadata))
  _ -> pure (toolError "cart_id and slot_metadata are both required")

cancelReservation :: Config -> [(ArgumentName, ArgumentValue)] -> IO ToolResult
cancelReservation config args = case lookup "reservation_id" args of
  Just rid -> withEnv config "cart" (\env -> Walmart.cancelReservation env (ReservationId rid))
  Nothing  -> pure (toolError "reservation_id is required")

setStore :: Config -> [(ArgumentName, ArgumentValue)] -> IO ToolResult
setStore config args = case (lookup "cart_id" args, lookup "store_id" args) of
  (Just cid, Just sid) -> withEnv config "cart" (\env -> Walmart.setDeliveryStore env (CartId cid) (StoreId sid))
  _ -> pure (toolError "cart_id and store_id are both required")

-- | One store's answer to one query: the first in-stock product, if any.
data StoreHit = StoreHit
  { hitQuery   :: Text
  , hitProduct :: Maybe ProductSummary
  }

instance Aeson.ToJSON StoreHit where
  toJSON h = Aeson.object
    [ "query"    Aeson..= hitQuery h
    , "in_stock" Aeson..= maybe False (const True) (hitProduct h)
    , "product"  Aeson..= hitProduct h
    ]

data StoreReport = StoreReport
  { reportStore   :: StoreId
  , reportHits    :: [StoreHit]
  , reportInStock :: Int
  }

instance Aeson.ToJSON StoreReport where
  toJSON r = Aeson.object
    [ "store_id"       Aeson..= reportStore r
    , "in_stock_count" Aeson..= reportInStock r
    , "results"        Aeson..= reportHits r
    ]

compareStores :: Config -> [(ArgumentName, ArgumentValue)] -> IO ToolResult
compareStores config args =
  case (lookup "cart_id" args, lookup "store_ids" args, lookup "queries" args) of
    (Just cid, Just rawStores, Just rawQueries) ->
      let stores = map (StoreId . T.strip) (filter (not . T.null) (T.splitOn "," rawStores))
          queries = filter (not . T.null) (map T.strip (T.splitOn "|" rawQueries))
          category = CategoryId <$> lookup "category_id" args
      in if null stores || null queries
        then pure (toolError "store_ids and queries must each name at least one entry")
        else withEnv config "comparison" (\env -> compareAt env (CartId cid) category stores queries)
    _ -> pure (toolError "cart_id, store_ids and queries are all required")

-- | Visit each store, search every query there, and put the cart back
-- where it was. The report names the original store and whether it
-- was restored, so a failed restore is never silent.
compareAt
  :: Walmart.Env -> CartId -> Maybe CategoryId -> [StoreId] -> [Text]
  -> IO (Either WalmartError Aeson.Value)
compareAt env cid category stores queries = do
  before <- Walmart.getCart env
  case before of
    Left err -> pure (Left err)
    Right cart -> do
      let origin = cartStoreId cart
      reports <- visit stores
      restored <- Walmart.setDeliveryStore env cid origin
      pure $ case reports of
        Left err -> Left err
        Right rs -> Right $ Aeson.object
          [ "original_store" Aeson..= origin
          , "restored"       Aeson..= either (const False) ((== origin) . cartStoreId) restored
          , "restore_error"  Aeson..= either (Just . renderWalmartError) (const Nothing) restored
          , "stores"         Aeson..= rs
          ]
  where
    visit [] = pure (Right [])
    visit (sid : rest) = do
      switched <- Walmart.setDeliveryStore env cid sid
      case switched of
        Left err -> pure (Left err)
        Right _ -> do
          hits <- searchAll queries
          case hits of
            Left err -> pure (Left err)
            Right hs -> fmap (StoreReport sid hs (length (filter (maybe False (const True) . hitProduct) hs)) :) <$> visit rest
    searchAll [] = pure (Right [])
    searchAll (q : qs) = do
      found <- Walmart.searchProducts env SearchQuery
        { sqTerm = q, sqCategoryId = category, sqPage = 1, sqLimit = 5 }
      case found of
        Left err -> pure (Left err)
        Right result ->
          let inStock = [ p | p <- srProducts result, psAvailability p == Just "In stock" ]
              hit = StoreHit q (case inStock of { (p : _) -> Just p; [] -> Nothing })
          in fmap (hit :) <$> searchAll qs

listSlots :: Config -> [(ArgumentName, ArgumentValue)] -> IO ToolResult
listSlots config args = case parseIntent (lookup "fulfillment" args) of
  Left err -> pure (toolError err)
  Right intent -> withEnv config "slots" (\env -> Walmart.getSlots env intent)

parseIntent :: Maybe Text -> Either Text FulfillmentIntent
parseIntent Nothing           = Right DeliveryIntent
parseIntent (Just "delivery") = Right DeliveryIntent
parseIntent (Just "pickup")   = Right PickupIntent
parseIntent (Just other)      = Left ("fulfillment must be delivery or pickup, got: " <> other)

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
renderWalmartError (WalmartRenderFailed msg) =
  "Could not render the product page: " <> msg
renderWalmartError (WalmartInvalidVariables messages) =
  "Walmart accepted the operation but not its variables:\n" <> T.unlines messages

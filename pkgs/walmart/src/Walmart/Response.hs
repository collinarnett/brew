{-# LANGUAGE OverloadedStrings #-}

-- | Decoding Walmart's GraphQL responses into this library's types.
--
-- These are pure functions over decoded JSON, so a captured response is
-- all it takes to exercise them.
module Walmart.Response
  ( parseOrderSummaries
  , parseWalmartOrder
  , parseSearchResult
  , graphQLRejection
  ) where

import Data.Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (Parser, parseEither)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Monoid (First (..))
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Data.Vector qualified as V
import Money (Discrete, discrete)

import Walmart.Types

parseOrderSummaries :: Value -> Either String [OrderSummary]
parseOrderSummaries = parseEither $ withObject "response" $ \obj -> do
  d <- obj .: "data"
  hist <- d .: "orderHistoryV2"
  groups <- hist .: "orderGroups"
  traverse parseOrderGroup groups

parseOrderGroup :: Value -> Parser OrderSummary
parseOrderGroup = withObject "orderGroup" $ \obj -> do
  orderId   <- OrderId <$> obj .: "orderId"
  orderType <- obj .: "type" :: Parser Text
  itemCount <- obj .: "itemCount"
  status    <- parseStatusText obj
  pure OrderSummary
    { osOrderId   = orderId
    -- Walmart's type field carries many fulfillment values (delivery,
    -- pickup, shipping, ...); getOrder only needs to know whether the
    -- order was placed in store, so everything else is Online.
    , osChannel   = if orderType == "IN_STORE" then InStore else Online
    , osItemCount = itemCount
    , osStatus    = status
    }

parseStatusText :: Object -> Parser (Maybe Text)
parseStatusText obj = do
  mStatus <- obj .:? "status"
  case mStatus of
    Nothing -> pure Nothing
    Just status -> do
      mMsg <- status .:? "message"
      case mMsg of
        Nothing  -> pure Nothing
        Just msg -> do
          parts <- msg .: "parts"
          texts <- traverse (\p -> p .: "text") parts
          pure (Just (mconcat texts))

parseWalmartOrder :: Value -> Either String WalmartOrder
parseWalmartOrder = parseEither $ withObject "response" $ \obj -> do
  d <- obj .: "data"
  order <- d .: "order"
  parseOrderDetail order

parseOrderDetail :: Value -> Parser WalmartOrder
parseOrderDetail = withObject "order" $ \obj -> do
  orderId   <- OrderId <$> obj .: "id"
  orderDate <- obj .: "orderDate"
  groups    <- findGroups obj
  items     <- concat <$> traverse parseItemGroup (V.toList groups)
  pure WalmartOrder
    { woOrderId   = orderId
    , woOrderDate = orderDate
    , woItems     = items
    }

findGroups :: Object -> Parser (V.Vector Value)
findGroups obj =
  case getFirst (foldMap asItemGroups (KM.elems obj)) of
    Just groups -> pure groups
    Nothing     -> fail "no groups key found in order"

asItemGroups :: Value -> First (V.Vector Value)
asItemGroups (Array arr)
  | not (V.null arr)
  , Object first <- V.head arr
  , KM.member "items" first = First (Just arr)
asItemGroups _ = First Nothing

parseItemGroup :: Value -> Parser [WalmartItem]
parseItemGroup = withObject "group" $ \obj -> do
  items <- obj .: "items"
  traverse parseWalmartItem items

parseWalmartItem :: Value -> Parser WalmartItem
parseWalmartItem = withObject "item" $ \obj -> do
  quantity    <- obj .: "quantity"
  productInfo <- obj .: "productInfo"
  name        <- productInfo .: "name"
  usItemId    <- UsItemId <$> productInfo .: "usItemId"
  salesUnit   <- parseSalesUnitType =<< productInfo .: "salesUnitType"
  linePrice   <- parseMaybeLinePrice obj
  pure WalmartItem
    { wiName          = name
    , wiQuantity      = quantity
    , wiLinePrice     = linePrice
    , wiUsItemId      = usItemId
    , wiSalesUnitType = salesUnit
    }

parseSalesUnitType :: Text -> Parser SalesUnitType
parseSalesUnitType "EACH"        = pure Each
parseSalesUnitType "EACH_WEIGHT" = pure EachWeight
parseSalesUnitType "PACK_WEIGHT" = pure PackWeight
parseSalesUnitType other         = fail ("unknown salesUnitType: " <> show other)

parseMaybeLinePrice :: Object -> Parser (Maybe (Discrete "USD" "cent"))
parseMaybeLinePrice obj = do
  mPriceInfo <- obj .:? "priceInfo"
  case mPriceInfo of
    Nothing -> pure Nothing
    Just priceInfo -> do
      mLinePrice <- priceInfo .:? "linePrice"
      case mLinePrice of
        Nothing -> pure Nothing
        Just lp -> Just . dollarsToCents <$> lp .: "value"

dollarsToCents :: Scientific -> Discrete "USD" "cent"
dollarsToCents s = discrete (round (s * 100))


parseSearchResult :: Value -> Either String SearchResult
parseSearchResult = parseEither $ withObject "response" $ \obj -> do
  d <- obj .: "data"
  products <- parseItemStacks =<< d .: "search"
  categories <- parseCategoryFacets =<< d .:? "contentLayout" .!= Object mempty
  store <- parseStoreContext =<< d .:? "contentLayout" .!= Object mempty
  pure SearchResult
    { srProducts   = products
    , srCategories = categories
    , srStore      = store
    }

parseItemStacks :: Value -> Parser [ProductSummary]
parseItemStacks = withObject "search" $ \obj -> do
  result <- obj .: "searchResult"
  stacks <- result .: "itemStacks" :: Parser [Value]
  concat <$> traverse parseItemStack stacks

parseItemStack :: Value -> Parser [ProductSummary]
parseItemStack = withObject "itemStack" $ \obj -> do
  items <- obj .:? "itemsV2" .!= ([] :: [Value])
  catMaybes <$> traverse parseTile items

-- | Walmart pads a result stack with advertising and layout tiles that
-- carry no item at all. Only the ones it types as products are read, so
-- a product that arrives malformed still fails rather than being
-- quietly counted as an advert.
parseTile :: Value -> Parser (Maybe ProductSummary)
parseTile = withObject "tile" $ \obj -> do
  typename <- obj .:? "__typename" .!= ("" :: Text)
  if typename == "Product"
    then Just <$> parseProductSummary (Object obj)
    else pure Nothing

parseProductSummary :: Value -> Parser ProductSummary
parseProductSummary = withObject "item" $ \obj -> do
  usItemId     <- UsItemId <$> obj .: "usItemId"
  name         <- obj .: "name"
  brand        <- obj .:? "brand"
  description  <- obj .:? "shortDescription"
  department   <- obj .:? "departmentName"
  categoryPath <- parseCategoryPath obj
  price        <- parseCurrentPrice obj
  unitPrice    <- parseUnitPrice obj
  availability <- parseAvailability obj
  fulfillment  <- parseFulfillment obj
  pure ProductSummary
    { psUsItemId      = usItemId
    , psName          = name
    , psBrand         = brand
    , psPrice         = price
    , psPricePerUnit  = unitPrice
    , psAvailability  = availability
    , psDescription   = description
    , psDepartment    = department
    , psCategoryPath  = categoryPath
    , psFulfillment   = fulfillment
    }

parseCategoryPath :: Object -> Parser (Maybe CategoryId)
parseCategoryPath obj = do
  mCategory <- obj .:? "category"
  case mCategory of
    Nothing -> pure Nothing
    Just category -> fmap CategoryId <$> category .:? "categoryPathId"

parseCurrentPrice :: Object -> Parser (Maybe (Discrete "USD" "cent"))
parseCurrentPrice obj = do
  mPriceInfo <- obj .:? "priceInfo"
  case mPriceInfo of
    Nothing -> pure Nothing
    Just priceInfo -> do
      mCurrent <- priceInfo .:? "currentPrice"
      case mCurrent of
        Nothing -> pure Nothing
        Just current -> fmap dollarsToCents <$> current .:? "price"

parseUnitPrice :: Object -> Parser (Maybe Text)
parseUnitPrice obj = do
  mPriceInfo <- obj .:? "priceInfo"
  case mPriceInfo of
    Nothing -> pure Nothing
    Just priceInfo -> do
      mUnit <- priceInfo .:? "unitPrice"
      case mUnit of
        Nothing -> pure Nothing
        Just unit -> unit .:? "priceString"

parseAvailability :: Object -> Parser (Maybe Text)
parseAvailability obj = do
  mStatus <- obj .:? "availabilityStatusV2"
  case mStatus of
    Nothing -> pure Nothing
    Just status -> status .:? "display"

-- | The department facet Walmart offers alongside results. Its values
-- are the category ids a follow-up search can be narrowed with, so a
-- caller never has to know one in advance.
parseCategoryFacets :: Value -> Parser [CategoryFacet]
parseCategoryFacets = withObject "contentLayout" $ \obj -> do
  modules <- obj .:? "modules" .!= ([] :: [Value])
  concat <$> traverse parseModuleFacets modules

parseModuleFacets :: Value -> Parser [CategoryFacet]
parseModuleFacets = withObject "module" $ \obj -> do
  mConfigs <- obj .:? "configs"
  case mConfigs of
    Nothing -> pure []
    Just configs -> do
      facets <- configs .:? "allSortAndFilterFacets" .!= ([] :: [Value])
      concat <$> traverse parseFacet facets

parseFacet :: Value -> Parser [CategoryFacet]
parseFacet = withObject "facet" $ \obj -> do
  facetType <- obj .:? "type" .!= ("" :: Text)
  if facetType /= "cat_id"
    then pure []
    else do
      values <- obj .:? "values" .!= ([] :: [Value])
      traverse parseFacetValue values

parseFacetValue :: Value -> Parser CategoryFacet
parseFacetValue = withObject "facetValue" $ \obj -> do
  categoryId <- CategoryId <$> obj .: "id"
  name       <- obj .: "name"
  count      <- obj .:? "count"
  pure CategoryFacet { cfId = categoryId, cfName = name, cfCount = count }

-- | The errors from a response that carries no data.
--
-- Walmart answers a persisted query it does not recognise with HTTP 200
-- and a GraphQL errors body rather than a status code, so a response
-- shaped like this is a refusal however healthy the transport looked.
-- A response with both data and errors is a partial success and is left
-- alone.
graphQLRejection :: Value -> Maybe Text
graphQLRejection value = case value of
  Object obj
    | Nothing <- KM.lookup "data" obj
    , Just errs <- KM.lookup "errors" obj -> Just (renderErrors errs)
  _notARejection -> Nothing
  where
    renderErrors errs = case errs of
      Array messages -> T.intercalate "; " (map messageOf (V.toList messages))
      other          -> T.pack (show other)
    messageOf (Object err) = case KM.lookup "message" err of
      Just (String msg) -> msg
      other             -> T.pack (show other)
    messageOf other = T.pack (show other)

-- | Collapse Walmart's fulfillment entries to one per method, keeping
-- the soonest date offered. The raw list repeats a method once per
-- slot, most of them undated.
parseFulfillment :: Object -> Parser [FulfillmentOption]
parseFulfillment obj = do
  entries <- obj .:? "fulfillmentSummary" .!= ([] :: [Value])
  offered <- traverse parseFulfillmentEntry entries
  pure (map toOption (Map.toAscList (Map.fromListWith earlier offered)))
  where
    earlier a b = case (a, b) of
      (Just x, Just y) -> Just (min x y)
      (Just x, Nothing) -> Just x
      (Nothing, other)  -> other
    toOption (method, earliest) =
      FulfillmentOption { foMethod = method, foEarliest = earliest }

parseFulfillmentEntry :: Value -> Parser (Fulfillment, Maybe UTCTime)
parseFulfillmentEntry = withObject "fulfillmentSummary" $ \obj -> do
  tag <- obj .:? "fulfillment" .!= ("" :: Text)
  date <- obj .:? "deliveryDate"
  pure (toFulfillment tag, date)

toFulfillment :: Text -> Fulfillment
toFulfillment "DELIVERY" = Delivery
toFulfillment "PICKUP"   = Pickup
toFulfillment "SHIPPING" = Shipping
toFulfillment other      = UnknownFulfillment other

-- | The store Walmart resolved for this search. It reports one whether
-- or not a store was ever chosen, so recording it keeps a stock answer
-- from being ambiguous about where it applies.
parseStoreContext :: Value -> Parser (Maybe StoreContext)
parseStoreContext = withObject "contentLayout" $ \obj -> do
  mMetadata <- obj .:? "pageMetadata"
  case mMetadata of
    Nothing -> pure Nothing
    Just metadata -> do
      mLocation <- metadata .:? "location"
      case mLocation of
        Nothing -> pure Nothing
        Just location -> do
          mStoreId <- location .:? "storeId"
          postalCode <- location .:? "postalCode"
          pure $ fmap (\sid -> StoreContext { scStoreId = sid, scPostalCode = postalCode }) mStoreId

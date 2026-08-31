{-# LANGUAGE OverloadedStrings #-}

-- | Decoding Walmart's GraphQL responses into this library's types.
--
-- These are pure functions over decoded JSON, so a captured response is
-- all it takes to exercise them.
module Walmart.Response
  ( parseOrderSummaries
  , parseWalmartOrder
  , parseSearchResult
  , parseStores
  , parseCart
  , parseCartUpdate
  , parseReservedCart
  , parseCancelledCart
  , parseStoreSwitchedCart
  , parseSlotSchedule
  , extractNextData
  , parseProductDetail
  , netContentSpecifications
  , Rejection (..)
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
import Data.Time (Day, UTCTime, zonedTimeToUTC)
import Data.Time.Format.ISO8601 (iso8601ParseM)
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
  offerId      <- OfferId <$> obj .: "offerId"
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
    , psOfferId       = offerId
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
-- | Why a gateway refused a request outright.
data Rejection
    -- | Every error is a variables validation, so the hash was accepted
    -- and the request itself is wrong. Each message names a variable.
  = VariablesRejected [Text]
    -- | Anything else: the persisted query is unknown or retired.
  | QueryRejected Text
  deriving stock (Show, Eq)

graphQLRejection :: Value -> Maybe Rejection
graphQLRejection value = case value of
  Object obj
    | Nothing <- KM.lookup "data" obj
    , Just errs <- KM.lookup "errors" obj -> Just (classifyErrors errs)
  _notARejection -> Nothing
  where
    classifyErrors errs = case errs of
      Array messages
        | not (V.null messages), all isValidation messages ->
            VariablesRejected (map messageOf (V.toList messages))
        | otherwise -> QueryRejected (T.intercalate "; " (map messageOf (V.toList messages)))
      other -> QueryRejected (T.pack (show other))
    isValidation (Object err) = case KM.lookup "extensions" err of
      Just (Object ext) | Just (String code) <- KM.lookup "code" ext -> "VALIDATION_" `T.isPrefixOf` code
      _noCode -> False
    isValidation _ = False
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

parseStores :: Value -> Either String [Store]
parseStores = parseEither $ withObject "response" $ \obj -> do
  d <- obj .: "data"
  nearby <- d .: "nearByNodes"
  nodes <- nearby .: "nodes"
  traverse parseStore nodes

parseStore :: Value -> Parser Store
parseStore = withObject "node" $ \obj -> do
  sid      <- StoreId <$> obj .: "id"
  name     <- obj .: "displayName"
  address  <- obj .: "address"
  city     <- address .: "city"
  state    <- address .: "state"
  postal   <- PostalCode <$> address .: "postalCode"
  distance <- (.: "value") =<< obj .: "nodeDistance"
  caps     <- obj .:? "capabilities" .!= ([] :: [Object])
  access   <- traverse (fmap parseAccessType . (.: "accessPointType")) caps
  pure Store
    { storeId            = sid
    , storeName          = name
    , storeCity          = city
    , storeState         = state
    , storePostalCode    = postal
    , storeDistanceMiles = distance
    , storeAccessTypes   = dedupe access
    }
  where
    dedupe = Map.keys . Map.fromList . map (\a -> (a, ()))

parseAccessType :: Text -> AccessType
parseAccessType "DELIVERY_ADDRESS" = DeliveryAddress
parseAccessType "PICKUP_INSTORE"   = PickupInStore
parseAccessType "PICKUP_CURBSIDE"  = PickupCurbside
parseAccessType other              = UnknownAccessType other

parseCart :: Value -> Either String Cart
parseCart = parseEither $ withObject "response" $ \obj -> do
  d <- obj .: "data"
  parseCartObject =<< d .: "cart"

-- | A cart mutation answers with the lines it left and their subtotal.
parseCartUpdate :: Value -> Either String CartReceipt
parseCartUpdate = parseEither $ withObject "response" $ \obj -> do
  d <- obj .: "data"
  cart <- d .: "updateItems"
  cid <- CartId <$> cart .: "id"
  lineItems <- traverse parseReceiptLine =<< cart .:? "lineItems" .!= []
  subtotal <- traverse (\pd -> dollarsToCents <$> ((.: "value") =<< pd .: "subTotal")) =<< cart .:? "priceDetails"
  pure CartReceipt { crCartId = cid, crLines = lineItems, crSubtotal = subtotal }

parseReceiptLine :: Value -> Parser ReceiptLine
parseReceiptLine = withObject "lineItem" $ \obj -> do
  item     <- obj .: "product"
  usItemId <- UsItemId <$> item .: "usItemId"
  offerId  <- OfferId <$> item .: "offerId"
  quantity <- obj .: "quantity"
  price    <- dollarsToCents <$> ((.: "value") =<< (.: "linePrice") =<< obj .: "priceInfo")
  pure ReceiptLine
    { rlUsItemId  = usItemId
    , rlOfferId   = offerId
    , rlQuantity  = quantity
    , rlLinePrice = price
    }

parseCartObject :: Object -> Parser Cart
parseCartObject cart = do
  cid <- CartId <$> cart .: "id"
  fulfillment <- cart .: "fulfillment"
  -- Walmart reports the store id as a number here and as a string
  -- everywhere else.
  sid <- StoreId . T.pack . show <$> (fulfillment .: "storeId" :: Parser Int)
  intent <- parseIntent =<< fulfillment .: "intent"
  explicit <- fulfillment .:? "isExplicitIntent"
  lineItems <- traverse parseCartLine =<< cart .:? "lineItems" .!= []
  totals <- traverse parseCartTotals =<< cart .:? "priceDetails"
  reservation <- traverse parseReservation =<< fulfillment .:? "reservation"
  pure Cart
    { cartId             = cid
    , cartStoreId        = sid
    , cartIntent         = intent
    , cartStoreChoice    = case explicit of
        Just True  -> ChosenStore
        Just False -> InferredStore
        Nothing    -> UnstatedStore
    , cartLines          = lineItems
    , cartTotals         = totals
    , cartReservation    = reservation
    }

-- | Each cart mutation answers with the cart it produced, under its
-- own name.
parseReservedCart, parseCancelledCart, parseStoreSwitchedCart :: Value -> Either String Cart
parseReservedCart = parseEither $ withObject "response" $ \obj ->
  parseCartObject =<< (.: "reserveSlot") =<< obj .: "data"
parseCancelledCart = parseEither $ withObject "response" $ \obj ->
  parseCartObject =<< (.: "cancelReservation") =<< obj .: "data"
parseStoreSwitchedCart = parseEither $ withObject "response" $ \obj ->
  parseCartObject =<< (.: "setDeliveryStore") =<< (.: "fulfillmentMutations") =<< obj .: "data"

parseReservation :: Object -> Parser Reservation
parseReservation obj = do
  rid    <- ReservationId <$> obj .: "id"
  expiry <- parseInstant =<< obj .: "expiryTime"
  held   <- obj .: "reservedSlot"
  sid    <- SlotId <$> held .: "id"
  kind   <- held .: "__typename"
  timing <- parseSlotTiming kind held
  fee    <- dollarsToCents <$> ((.: "value") =<< (.: "total") =<< held .: "price")
  pure Reservation
    { reservationId     = rid
    , reservationExpiry = expiry
    , reservationSlot   = ReservedSlot { rsSlotId = sid, rsTiming = timing, rsFee = fee }
    }

parseCartLine :: Value -> Parser CartLine
parseCartLine = withObject "lineItem" $ \obj -> do
  item     <- obj .: "product"
  usItemId <- UsItemId <$> item .: "usItemId"
  offerId  <- OfferId <$> item .: "offerId"
  name     <- item .: "name"
  unit     <- parseSalesUnitType =<< item .: "salesUnitType"
  avail    <- item .:? "availabilityStatus"
  quantity <- obj .: "quantity"
  price    <- dollarsToCents <$> ((.: "value") =<< (.: "linePrice") =<< obj .: "priceInfo")
  pure CartLine
    { clUsItemId      = usItemId
    , clOfferId       = offerId
    , clName          = name
    , clQuantity      = quantity
    , clSalesUnitType = unit
    , clLinePrice     = price
    , clAvailability  = avail
    }

parseCartTotals :: Object -> Parser CartTotals
parseCartTotals obj = do
  subtotal <- amountOf =<< obj .: "subTotal"
  total    <- traverse amountOf =<< obj .:? "grandTotal"
  minimum_ <- traverse amountOf =<< obj .:? "minimumThreshold"
  fee      <- traverse amountOf =<< obj .:? "belowMinimumFee"
  pure CartTotals
    { ctSubtotal        = subtotal
    , ctEstimatedTotal  = total
    , ctOrderMinimum    = minimum_
    , ctBelowMinimumFee = fee
    }
  where
    amountOf :: Object -> Parser (Discrete "USD" "cent")
    amountOf o = dollarsToCents <$> o .: "value"

parseIntent :: Text -> Parser FulfillmentIntent
parseIntent "DELIVERY" = pure DeliveryIntent
parseIntent "PICKUP"   = pure PickupIntent
parseIntent other      = fail ("unknown fulfillment intent: " <> show other)

parseSlotSchedule :: Value -> Either String SlotSchedule
parseSlotSchedule = parseEither $ withObject "response" $ \obj -> do
  d <- obj .: "data"
  slots <- d .: "slots"
  accessPoints <- traverse parseAccessPoint =<< slots .:? "accessPoints" .!= []
  days <- traverse parseSlotDay =<< slots .:? "slotDays" .!= []
  pure SlotSchedule { ssAccessPoints = accessPoints, ssDays = days }

parseAccessPoint :: Value -> Parser SlotAccessPoint
parseAccessPoint = withObject "accessPoint" $ \obj -> do
  apid <- AccessPointId <$> obj .: "id"
  name <- obj .: "displayName"
  sid  <- StoreId <$> obj .: "assortmentStoreId"
  pure SlotAccessPoint { apId = apid, apName = name, apStoreId = sid }

parseSlotDay :: Value -> Parser SlotDay
parseSlotDay = withObject "slotDay" $ \obj -> do
  day   <- parseDay =<< obj .: "day"
  slots <- traverse parseSlot =<< obj .:? "eachDaySlots" .!= []
  pure SlotDay { sdDay = day, sdSlots = slots }

parseSlot :: Value -> Parser Slot
parseSlot = withObject "slot" $ \obj -> do
  sid       <- SlotId <$> obj .: "id"
  apid      <- AccessPointId <$> obj .: "accessPointId"
  typename  <- obj .: "__typename"
  timing    <- parseSlotTiming typename obj
  available <- obj .: "available"
  fee       <- dollarsToCents <$> ((.: "value") =<< (.: "total") =<< obj .: "price")
  expiry    <- traverse parseInstant =<< obj .:? "slotExpiryTime"
  metadata  <- fmap SlotMetadata <$> obj .:? "slotMetadata"
  pure Slot
    { slotId          = sid
    , slotAccessPoint = apid
    , slotTiming      = timing
    , slotAvailable   = available
    , slotFee         = fee
    , slotExpiry      = expiry
    , slotMetadata    = metadata
    }

parseSlotTiming :: Text -> Object -> Parser SlotTiming
parseSlotTiming "RegularSlot" obj =
  Scheduled <$> (parseInstant =<< obj .: "startTime") <*> (parseInstant =<< obj .: "endTime")
parseSlotTiming "DynamicExpressSlot" obj = Express <$> obj .: "slaInMins"
parseSlotTiming other _ = pure (UnknownSlotKind other)

-- | Walmart stamps slot times with the store's UTC offset.
parseInstant :: Text -> Parser UTCTime
parseInstant raw = case iso8601ParseM (T.unpack raw) of
  Just zoned -> pure (zonedTimeToUTC zoned)
  Nothing    -> fail ("not an ISO 8601 timestamp: " <> show raw)

parseDay :: Text -> Parser Day
parseDay raw = case iso8601ParseM (T.unpack raw) of
  Just day -> pure day
  Nothing  -> fail ("not an ISO 8601 date: " <> show raw)

-- | The JSON a Next.js page embeds for its own hydration, which is
-- where a Walmart product page keeps the product.
extractNextData :: Text -> Maybe Text
extractNextData html =
  let (_, rest) = T.breakOn "<script id=\"__NEXT_DATA__\"" html
  in if T.null rest then Nothing else
       let afterTag = T.drop 1 (T.dropWhile (/= '>') rest)
           payload  = fst (T.breakOn "</script>" afterTag)
       in if T.null payload then Nothing else Just payload

-- | Specification rows that state how much the package holds, in the
-- order they are preferred when several appear.
netContentSpecifications :: [Text]
netContentSpecifications = ["Net content statement", "Weight", "Product net content parent"]

parseProductDetail :: Value -> Either String ProductDetail
parseProductDetail = parseEither $ withObject "page" $ \page -> do
  props <- page .: "props"
  pageProps <- props .: "pageProps"
  initial <- pageProps .: "initialData"
  d <- initial .: "data"
  item <- d .: "product"
  idml <- d .:? "idml" .!= mempty
  usItemId <- UsItemId <$> item .: "usItemId"
  offerId  <- OfferId <$> item .: "offerId"
  name     <- item .: "name"
  brand    <- item .:? "brand"
  upc      <- fmap Upc <$> item .:? "upc"
  price    <- parseCurrentPrice item
  unit     <- parseUnitPrice item
  category <- parseCategoryNames item
  specs    <- traverse parseSpecification =<< idml .:? "specifications" .!= []
  ingredients <- parseIngredients idml
  description <- idml .:? "shortDescription"
  pure ProductDetail
    { pdUsItemId       = usItemId
    , pdOfferId        = offerId
    , pdName           = name
    , pdBrand          = brand
    , pdUpc            = upc
    , pdPrice          = price
    , pdPricePerUnit   = unit
    , pdCategoryPath   = category
    , pdIngredients    = ingredients
    , pdNetContent     = netContent specs
    , pdSpecifications = specs
    , pdDescription    = description
    }
  where
    netContent specs = getFirst (foldMap (\wanted -> First (lookup wanted [ (specName s, specValue s) | s <- specs ])) netContentSpecifications)

parseSpecification :: Value -> Parser Specification
parseSpecification = withObject "specification" $ \obj ->
  Specification <$> obj .: "name" <*> obj .: "value"

parseIngredients :: Object -> Parser (Maybe Text)
parseIngredients idml = do
  mBlock <- idml .:? "ingredients"
  case mBlock of
    Nothing -> pure Nothing
    Just block -> do
      mStatement <- block .:? "ingredients"
      case mStatement of
        Nothing -> pure Nothing
        Just statement -> statement .:? "value"

parseCategoryNames :: Object -> Parser [Text]
parseCategoryNames item = do
  mCategory <- item .:? "category"
  case mCategory of
    Nothing -> pure []
    Just category -> do
      path <- category .:? "path" .!= ([] :: [Object])
      traverse (.: "name") path

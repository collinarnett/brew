{-# LANGUAGE OverloadedStrings #-}

-- | JSON codecs for Walmart API responses.
--
-- All parsing happens at the boundary via FromJSON instances.
-- Inner modules work only with typed domain values.
module WalmartGrocy.JSON
  ( parseOrderSummaries
  , parseWalmartOrder
  , parseGrocyProducts
  ) where

import Data.Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (Parser, parseEither)
import Data.Monoid (First (..))
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Vector qualified as V

import WalmartGrocy.Types

-- ---------------------------------------------------------------------
-- PurchaseHistoryV2 response
-- ---------------------------------------------------------------------

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
  statusText <- parseStatusText obj
  pure OrderSummary
    { osOrderId   = orderId
    , osIsInStore  = orderType == "IN_STORE"
    , osItemCount = itemCount
    , osStatus    = statusText
    }

parseStatusText :: Object -> Parser Text
parseStatusText obj = do
  mStatus <- obj .:? "status"
  case mStatus of
    Nothing -> pure ""
    Just status -> do
      mMsg <- status .:? "message"
      case mMsg of
        Nothing  -> pure ""
        Just msg -> do
          parts <- msg .: "parts"
          texts <- traverse (\p -> p .: "text") parts
          pure (mconcat texts)

-- ---------------------------------------------------------------------
-- getOrder response
-- ---------------------------------------------------------------------

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

-- | Find the groups array by structure, not by key name.
-- The key is a GraphQL alias (e.g. groups_2101) that changes
-- with schema versions. We match the first Array value whose
-- elements are Objects containing an "items" key.
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

parseMaybeLinePrice :: Object -> Parser (Maybe Scientific)
parseMaybeLinePrice obj = do
  mPriceInfo <- obj .:? "priceInfo"
  case mPriceInfo of
    Nothing -> pure Nothing
    Just priceInfo -> do
      mLinePrice <- priceInfo .:? "linePrice"
      case mLinePrice of
        Nothing -> pure Nothing
        Just lp -> Just <$> lp .: "value"

-- ---------------------------------------------------------------------
-- Grocy product list
-- ---------------------------------------------------------------------

parseGrocyProducts :: Value -> Either String [GrocyProduct]
parseGrocyProducts = parseEither $ withArray "products" $ \arr ->
  traverse parseGrocyProduct (V.toList arr)

parseGrocyProduct :: Value -> Parser GrocyProduct
parseGrocyProduct = withObject "product" $ \obj -> do
  pid  <- ProductId <$> obj .: "id"
  name <- obj .: "name"
  pure GrocyProduct { gpId = pid, gpName = name }

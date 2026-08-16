{-# LANGUAGE OverloadedStrings #-}

module Walmart.Types
  ( OrderId (..)
  , UsItemId (..)
  , OrderChannel (..)
  , SalesUnitType (..)
  , WalmartItem (..)
  , WalmartOrder (..)
  , OrderSummary (..)
  , WalmartError (..)
  , BodyPreview (..)
  ) where

import Data.Aeson (ToJSON (..), object, (.=))
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Time (UTCTime)
import Money (Discrete)

newtype OrderId = OrderId { unOrderId :: Text }
  deriving stock (Show, Eq, Ord)

instance ToJSON OrderId where
  toJSON = toJSON . unOrderId

newtype UsItemId = UsItemId { unUsItemId :: Text }
  deriving stock (Show, Eq, Ord)

instance ToJSON UsItemId where
  toJSON = toJSON . unUsItemId

-- | Where the order was placed. getOrder must be told which kind it is
-- fetching, so the summary records it.
data OrderChannel = InStore | Online
  deriving stock (Show, Eq)

instance ToJSON OrderChannel where
  toJSON InStore = "in_store"
  toJSON Online  = "online"

data SalesUnitType = Each | EachWeight | PackWeight
  deriving stock (Show, Eq)

instance ToJSON SalesUnitType where
  toJSON Each       = "each"
  toJSON EachWeight = "each_weight"
  toJSON PackWeight = "pack_weight"

data WalmartItem = WalmartItem
  { wiName          :: Text
  , wiQuantity      :: Scientific
  , wiLinePrice     :: Maybe (Discrete "USD" "cent")
  , wiUsItemId      :: UsItemId
  , wiSalesUnitType :: SalesUnitType
  } deriving stock (Show, Eq)

instance ToJSON WalmartItem where
  toJSON item = object
    [ "name"             .= wiName item
    , "quantity"         .= wiQuantity item
    , "line_price_cents" .= fmap toInteger (wiLinePrice item)
    , "us_item_id"       .= wiUsItemId item
    , "sales_unit_type"  .= wiSalesUnitType item
    ]

data WalmartOrder = WalmartOrder
  { woOrderId   :: OrderId
  , woOrderDate :: UTCTime
  , woItems     :: [WalmartItem]
  } deriving stock (Show)

instance ToJSON WalmartOrder where
  toJSON order = object
    [ "order_id"   .= woOrderId order
    , "order_date" .= woOrderDate order
    , "items"      .= woItems order
    ]

data OrderSummary = OrderSummary
  { osOrderId   :: OrderId
  , osChannel   :: OrderChannel
  , osItemCount :: Int
  , osStatus    :: Maybe Text
  } deriving stock (Show)

instance ToJSON OrderSummary where
  toJSON summary = object
    [ "order_id"   .= osOrderId summary
    , "channel"    .= osChannel summary
    , "item_count" .= osItemCount summary
    , "status"     .= osStatus summary
    ]

-- | The first 200 characters of a response body, kept for diagnostics.
newtype BodyPreview = BodyPreview { unBodyPreview :: Text }
  deriving stock (Show, Eq)

data WalmartError
  = WalmartNetworkError Text
  | WalmartParseError Text String
  | WalmartBadRequest
  | WalmartRateLimited
  | WalmartAccessDenied
  | WalmartHttpError Int
  | WalmartJsonDecodeError String BodyPreview
  deriving stock (Show, Eq)

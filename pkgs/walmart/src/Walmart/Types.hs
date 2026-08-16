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

import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Time (UTCTime)
import Money (Discrete)

newtype OrderId = OrderId { unOrderId :: Text }
  deriving stock (Show, Eq, Ord)

newtype UsItemId = UsItemId { unUsItemId :: Text }
  deriving stock (Show, Eq, Ord)

-- | Where the order was placed. getOrder must be told which kind it is
-- fetching, so the summary records it.
data OrderChannel = InStore | Online
  deriving stock (Show, Eq)

data SalesUnitType = Each | EachWeight | PackWeight
  deriving stock (Show, Eq)

data WalmartItem = WalmartItem
  { wiName          :: Text
  , wiQuantity      :: Scientific
  , wiLinePrice     :: Maybe (Discrete "USD" "cent")
  , wiUsItemId      :: UsItemId
  , wiSalesUnitType :: SalesUnitType
  } deriving stock (Show, Eq)

data WalmartOrder = WalmartOrder
  { woOrderId   :: OrderId
  , woOrderDate :: UTCTime
  , woItems     :: [WalmartItem]
  } deriving stock (Show)

data OrderSummary = OrderSummary
  { osOrderId   :: OrderId
  , osChannel   :: OrderChannel
  , osItemCount :: Int
  , osStatus    :: Maybe Text
  } deriving stock (Show)

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

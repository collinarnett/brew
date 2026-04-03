{-# LANGUAGE OverloadedStrings #-}

module Walmart.Types
  ( OrderId (..)
  , UsItemId (..)
  , SalesUnitType (..)
  , WalmartItem (..)
  , WalmartOrder (..)
  , OrderSummary (..)
  , WalmartError (..)
  ) where

import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Time (UTCTime)
import Money (Discrete)

newtype OrderId = OrderId { unOrderId :: Text }
  deriving stock (Show, Eq, Ord)

newtype UsItemId = UsItemId { unUsItemId :: Text }
  deriving stock (Show, Eq, Ord)

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
  , osIsInStore :: Bool
  , osItemCount :: Int
  , osStatus    :: Text
  } deriving stock (Show)

data WalmartError
  = WalmartParseError Text String
  | WalmartHashRotated
  | WalmartRateLimited
  | WalmartAccessDenied Int
  | WalmartHttpError Int
  | WalmartJsonDecodeError String String
  deriving stock (Show, Eq)

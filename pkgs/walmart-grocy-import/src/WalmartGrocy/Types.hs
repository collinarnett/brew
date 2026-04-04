{-# LANGUAGE OverloadedStrings #-}

module WalmartGrocy.Types
  ( ProductId
  , ProductName
  , GrocyProduct
  , GrocyError (..)
  , Action (..)
  , ImportPlan (..)
  , ImportResult (..)
  , ImportOptions (..)
  , Verbosity (..)
  , AppError (..)
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)

import BrowserCookies (CookieError)
import Walmart.Types (OrderId, WalmartError, WalmartItem)

type ProductId = Int
type ProductName = Text
type GrocyProduct = (ProductId, ProductName)

data GrocyError
  = GrocyHttpError Text Int
  | GrocyParseError Text
  | GrocyEntityNotFound Text Text
  | GrocyProductNotFound Text
  | GrocyCreateError Text String
  deriving stock (Show, Eq)

data Action
  = CreateAndStock WalmartItem
  | StockExisting  WalmartItem GrocyProduct
  deriving stock (Show, Eq)

data ImportPlan = ImportPlan
  { ipOrderId   :: OrderId
  , ipOrderDate :: UTCTime
  , ipActions   :: [Action]
  } deriving stock (Show)

data ImportResult = ImportResult
  { irOrderId :: OrderId
  , irMatched :: [(WalmartItem, GrocyProduct)]
  , irCreated :: [(WalmartItem, GrocyProduct)]
  } deriving stock (Show)

data ImportOptions = ImportOptions
  { ioSince  :: Maybe UTCTime
  , ioLimit  :: Int
  , ioDryRun :: Bool
  , ioForce  :: Bool
  } deriving stock (Show)

data Verbosity = Quiet | Normal | Verbose | Debug
  deriving stock (Show, Eq, Ord)

data AppError
  = AppCookieError CookieError
  | AppWalmartError WalmartError
  | AppGrocyError GrocyError
  deriving stock (Show, Eq)

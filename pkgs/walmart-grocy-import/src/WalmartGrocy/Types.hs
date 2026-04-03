{-# LANGUAGE OverloadedStrings #-}

module WalmartGrocy.Types
  ( Action (..)
  , ImportPlan (..)
  , ImportResult (..)
  , ImportOptions (..)
  , Verbosity (..)
  , AppError (..)
  ) where

import Data.Time (UTCTime)

import BrowserCookies (CookieError)
import Grocy.Types (GrocyError, GrocyProduct)
import Walmart.Types (OrderId, WalmartError, WalmartItem)

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

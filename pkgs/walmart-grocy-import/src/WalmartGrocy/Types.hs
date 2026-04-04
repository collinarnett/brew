{-# LANGUAGE OverloadedStrings #-}

module WalmartGrocy.Types
  ( Action (..)
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
import WalmartGrocy.Grocy (GrocyError)

data Action
  = CreateAndStock WalmartItem
  | StockExisting  WalmartItem (Int, Text)
  deriving stock (Show, Eq)

data ImportPlan = ImportPlan
  { ipOrderId   :: OrderId
  , ipOrderDate :: UTCTime
  , ipActions   :: [Action]
  } deriving stock (Show)

data ImportResult = ImportResult
  { irOrderId :: OrderId
  , irMatched :: [(WalmartItem, (Int, Text))]
  , irCreated :: [(WalmartItem, (Int, Text))]
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

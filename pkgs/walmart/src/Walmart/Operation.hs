{-# LANGUAGE OverloadedStrings #-}

-- | The GraphQL operations this client addresses.
--
-- Everything an operation needs beyond its persisted query hash is
-- stated here: which gateway serves it, what the gateway calls it, and
-- what the request path looks like. Adding an operation is one
-- constructor and the branches the compiler then demands.
module Walmart.Operation
  ( Operation (..)
  , allOperations
  , operationName
  , Route (..)
  , routeOperation
  , routeUrl
  ) where

import Data.Text (Text)

import Walmart.Types (OperationName (..), QueryHash, unQueryHash)

data Operation
  = PurchaseHistory
  | GetOrder
  | Search
  deriving stock (Show, Eq, Ord, Enum, Bounded)

allOperations :: [Operation]
allOperations = [minBound .. maxBound]

operationName :: Operation -> OperationName
operationName PurchaseHistory = OperationName "PurchaseHistoryV2"
operationName GetOrder        = OperationName "getOrder"
operationName Search          = OperationName "Search"

-- | The orchestra gateway an operation is served from.
data Service = Cph | Orders | Snb

servicePath :: Service -> Text
servicePath Cph    = "cph"
servicePath Orders = "orders"
servicePath Snb    = "snb"

operationService :: Operation -> Service
operationService PurchaseHistory = Cph
operationService GetOrder        = Orders
operationService Search          = Snb

-- | A concrete request target: an operation plus whatever the gateway
-- expects after the hash. Item detail names its item in the path, so a
-- route carries it rather than leaving callers to build the URL.
data Route
  = PurchaseHistoryRoute
  | GetOrderRoute
  | SearchRoute
  deriving stock (Show, Eq)

routeOperation :: Route -> Operation
routeOperation PurchaseHistoryRoute = PurchaseHistory
routeOperation GetOrderRoute        = GetOrder
routeOperation SearchRoute          = Search

-- | What the gateway expects after the hash.
routeSuffix :: Route -> Text
routeSuffix PurchaseHistoryRoute = ""
routeSuffix GetOrderRoute        = ""
routeSuffix SearchRoute          = "/search"

walmartBase :: Text
walmartBase = "https://www.walmart.com"

routeUrl :: QueryHash -> Route -> Text
routeUrl hash route =
  let op = routeOperation route
  in walmartBase
     <> "/orchestra/" <> servicePath (operationService op)
     <> "/graphql/" <> unOperationName (operationName op)
     <> "/" <> unQueryHash hash
     <> routeSuffix route

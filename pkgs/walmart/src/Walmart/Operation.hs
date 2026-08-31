{-# LANGUAGE OverloadedStrings #-}

-- | The GraphQL operations this client addresses.
--
-- Everything an operation needs beyond its persisted query hash is
-- stated here: which gateway serves it, whether it reads or writes,
-- what the gateway calls it, and what the request path looks like.
-- Adding an operation is one constructor and the branches the compiler
-- then demands.
module Walmart.Operation
  ( Operation (..)
  , allOperations
  , operationName
  , operationTarget
  , Service (..)
  , allServices
  , servicePath
  , parseService
  , Kind (..)
  , kindLabel
  , parseKind
  , Target (..)
  , Route (..)
  , routeTarget
  , routeUrl
  ) where

import Data.Text (Text)

import Walmart.Types (OperationName (..), QueryHash, unQueryHash)

data Operation
  = PurchaseHistory
  | GetOrder
  | Search
  | FindStores
  | GetCart
  | GetSlots
  | UpdateItems
  | ReserveSlot
  | CancelReservation
  | SetDeliveryStore
  deriving stock (Show, Eq, Ord, Enum, Bounded)

allOperations :: [Operation]
allOperations = [minBound .. maxBound]

operationName :: Operation -> OperationName
operationName PurchaseHistory = OperationName "PurchaseHistoryV2"
operationName GetOrder        = OperationName "getOrder"
operationName Search          = OperationName "Search"
operationName FindStores      = OperationName "storeFinderNearbyNodesQuery"
operationName GetCart         = OperationName "getCart"
operationName GetSlots        = OperationName "getSlots"
operationName UpdateItems     = OperationName "updateItems"
operationName ReserveSlot     = OperationName "reserveSlotMutation"
operationName CancelReservation = OperationName "cancelReservation"
operationName SetDeliveryStore = OperationName "setDeliveryStore"

-- | The orchestra gateway an operation is served from. Walmart's
-- frontend names these by a key (@cecxo@, @cegateway@, ...) and maps
-- each key to a path segment under @/orchestra/@; the segment is what
-- a request needs.
data Service = Cph | Orders | Snb | Home | CartXo | Pdp
  deriving stock (Show, Eq, Ord, Enum, Bounded)

allServices :: [Service]
allServices = [minBound .. maxBound]

servicePath :: Service -> Text
servicePath Cph    = "cph"
servicePath Orders = "orders"
servicePath Snb    = "snb"
servicePath Home   = "home"
servicePath CartXo = "cartxo"
servicePath Pdp    = "pdp"

parseService :: Text -> Maybe Service
parseService raw = case filter ((== raw) . servicePath) allServices of
  [s] -> Just s
  _   -> Nothing

-- | Whether the operation reads or writes. The gateway takes a query's
-- variables in the URL and a mutation's in a POST body, and the
-- operation header names the kind.
data Kind = Query | Mutation
  deriving stock (Show, Eq)

kindLabel :: Kind -> Text
kindLabel Query    = "query"
kindLabel Mutation = "mutation"

parseKind :: Text -> Maybe Kind
parseKind "query"    = Just Query
parseKind "mutation" = Just Mutation
parseKind _          = Nothing

operationService :: Operation -> Service
operationService PurchaseHistory = Cph
operationService GetOrder        = Orders
operationService Search          = Snb
operationService FindStores      = Home
operationService GetCart         = CartXo
operationService GetSlots        = CartXo
operationService UpdateItems     = CartXo
operationService ReserveSlot     = CartXo
operationService CancelReservation = CartXo
operationService SetDeliveryStore = CartXo

operationKind :: Operation -> Kind
operationKind PurchaseHistory = Query
operationKind GetOrder        = Query
operationKind Search          = Query
operationKind FindStores      = Query
operationKind GetCart         = Query
operationKind GetSlots        = Query
operationKind UpdateItems     = Mutation
operationKind ReserveSlot     = Mutation
operationKind CancelReservation = Mutation
operationKind SetDeliveryStore = Mutation

-- | What a request needs to know about its operation once the hash is
-- resolved: the name the gateway registers it under, the gateway, the
-- kind, and whatever the gateway expects after the hash.
data Target = Target
  { targetName    :: OperationName
  , targetService :: Service
  , targetKind    :: Kind
  , targetSuffix  :: Text
  } deriving stock (Show, Eq)

operationTarget :: Operation -> Target
operationTarget op = Target
  { targetName    = operationName op
  , targetService = operationService op
  , targetKind    = operationKind op
  , targetSuffix  = ""
  }

-- | A concrete request target. The typed routes cover the operations
-- this client models; 'ProbeRoute' addresses any catalogued operation
-- by name, for learning a gateway's variables before modelling it.
data Route
  = PurchaseHistoryRoute
  | GetOrderRoute
  | SearchRoute
  | FindStoresRoute
  | GetCartRoute
  | GetSlotsRoute
  | UpdateItemsRoute
  | ReserveSlotRoute
  | CancelReservationRoute
  | SetDeliveryStoreRoute
  | ProbeRoute Target
  deriving stock (Show, Eq)

routeTarget :: Route -> Target
routeTarget PurchaseHistoryRoute = operationTarget PurchaseHistory
routeTarget GetOrderRoute        = operationTarget GetOrder
routeTarget SearchRoute          = (operationTarget Search) { targetSuffix = "/search" }
routeTarget FindStoresRoute      = operationTarget FindStores
routeTarget GetCartRoute         = operationTarget GetCart
routeTarget GetSlotsRoute        = operationTarget GetSlots
routeTarget UpdateItemsRoute     = operationTarget UpdateItems
routeTarget ReserveSlotRoute     = operationTarget ReserveSlot
routeTarget CancelReservationRoute = operationTarget CancelReservation
routeTarget SetDeliveryStoreRoute = operationTarget SetDeliveryStore
routeTarget (ProbeRoute target)  = target

walmartBase :: Text
walmartBase = "https://www.walmart.com"

routeUrl :: QueryHash -> Target -> Text
routeUrl hash target =
  walmartBase
  <> "/orchestra/" <> servicePath (targetService target)
  <> "/graphql/" <> unOperationName (targetName target)
  <> "/" <> unQueryHash hash
  <> targetSuffix target

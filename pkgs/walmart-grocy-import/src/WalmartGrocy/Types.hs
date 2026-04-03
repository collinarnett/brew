{-# LANGUAGE OverloadedStrings #-}

module WalmartGrocy.Types
  ( -- * Newtypes
    OrderId (..)
  , ProductId (..)
  , UsItemId (..)
  , EndpointUrl (..)

    -- * Walmart domain
  , SalesUnitType (..)
  , WalmartItem (..)
  , WalmartOrder (..)
  , OrderSummary (..)

    -- * Grocy domain
  , GrocyProduct (..)

    -- * Reconciliation
  , Action (..)
  , ImportPlan (..)
  , ImportResult (..)

    -- * Configuration
  , Verbosity (..)
  , GrocyEnv (..)
  , ImportOptions (..)
  , EndpointCache (..)
  ) where

import Data.Aeson qualified as Aeson
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Time (UTCTime)
import Network.HTTP.Client (Manager)

-- | Newtypes for compile-time ID safety.
newtype OrderId = OrderId { unOrderId :: Text }
  deriving stock (Show, Eq, Ord)

newtype ProductId = ProductId { unProductId :: Int }
  deriving stock (Show, Eq, Ord)

newtype UsItemId = UsItemId { unUsItemId :: Text }
  deriving stock (Show, Eq, Ord)

newtype EndpointUrl = EndpointUrl { unEndpointUrl :: Text }
  deriving stock (Show, Eq, Ord)

-- | How Walmart sells the item.
data SalesUnitType = Each | EachWeight | PackWeight
  deriving stock (Show, Eq)

-- | A single item from a Walmart order with exact pricing.
data WalmartItem = WalmartItem
  { wiName          :: Text
  , wiQuantity      :: Scientific
  , wiLinePrice     :: Maybe Scientific -- ^ cents as Scientific for now; see JSON.hs
  , wiUsItemId      :: UsItemId
  , wiSalesUnitType :: SalesUnitType
  } deriving stock (Show, Eq)

-- | Full order detail from getOrder.
data WalmartOrder = WalmartOrder
  { woOrderId   :: OrderId
  , woOrderDate :: UTCTime
  , woItems     :: [WalmartItem]
  } deriving stock (Show)

-- | Order summary from PurchaseHistoryV2.
data OrderSummary = OrderSummary
  { osOrderId   :: OrderId
  , osIsInStore :: Bool
  , osItemCount :: Int
  , osStatus    :: Text
  } deriving stock (Show)

-- | A product in the Grocy inventory.
data GrocyProduct = GrocyProduct
  { gpId   :: ProductId
  , gpName :: Text
  } deriving stock (Show, Eq)

-- | Pure description of what to do for a single item.
data Action
  = CreateAndStock WalmartItem
  | StockExisting  WalmartItem GrocyProduct
  deriving stock (Show, Eq)

-- | Pure reconciliation result for one order.
data ImportPlan = ImportPlan
  { ipOrderId   :: OrderId
  , ipOrderDate :: UTCTime
  , ipActions   :: [Action]
  } deriving stock (Show)

-- | Result after executing a plan against Grocy.
data ImportResult = ImportResult
  { irOrderId :: OrderId
  , irMatched :: [(WalmartItem, GrocyProduct)]
  , irCreated :: [(WalmartItem, GrocyProduct)]
  } deriving stock (Show)

-- | Logging verbosity.
data Verbosity = Quiet | Normal | Verbose | Debug
  deriving stock (Show, Eq, Ord)

-- | Grocy API connection.
data GrocyEnv = GrocyEnv
  { geBaseUrl :: Text
  , geApiKey  :: Text
  , geManager :: Manager
  }

-- | CLI options for the import command.
data ImportOptions = ImportOptions
  { ioSince  :: Maybe UTCTime
  , ioLimit  :: Int
  , ioDryRun :: Bool
  , ioForce  :: Bool
  } deriving stock (Show)

-- | Cached endpoint URLs with timestamp.
data EndpointCache = EndpointCache
  { ecTimestamp :: UTCTime
  , ecEndpoints :: Map Text EndpointUrl
  } deriving stock (Show)

instance Aeson.FromJSON EndpointCache where
  parseJSON = Aeson.withObject "EndpointCache" $ \obj -> do
    ts  <- obj Aeson..: "timestamp"
    eps <- obj Aeson..: "endpoints"
    pure EndpointCache
      { ecTimestamp = ts
      , ecEndpoints = Map.map EndpointUrl eps
      }

instance Aeson.ToJSON EndpointCache where
  toJSON ec = Aeson.object
    [ "timestamp" Aeson..= ecTimestamp ec
    , "endpoints" Aeson..= Map.map unEndpointUrl (ecEndpoints ec)
    ]

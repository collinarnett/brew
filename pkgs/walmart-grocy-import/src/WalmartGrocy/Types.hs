module WalmartGrocy.Types
  ( Action (..)
  , ExecutedAction (..)
  , ImportPlan (..)
  , ImportResult (..)
  , ImportOutcome (..)
  , ImportMode (..)
  , ImportOptions (..)
  , SetupConfig (..)
  , AppError (..)
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)

import BrowserCookies (CookieError)
import Grocy (GrocyError, Product)
import Walmart.Types (OrderId, WalmartError, WalmartItem)

-- | What reconciliation decided for one order item.
data Action
  = CreateAndStock WalmartItem
  | StockExisting  WalmartItem Product
  deriving stock (Show, Eq)

-- | What actually happened to one order item in Grocy.
data ExecutedAction
  = Stocked WalmartItem Product
  | Created WalmartItem Product
  deriving stock (Show, Eq)

data ImportPlan = ImportPlan
  { ipOrderId   :: OrderId
  , ipOrderDate :: UTCTime
  , ipActions   :: [Action]
  } deriving stock (Show)

data ImportResult = ImportResult
  { irOrderId :: OrderId
  , irActions :: [ExecutedAction]
  } deriving stock (Show)

-- | A dry run stops at the plans; only a real run has results to
-- record in the state file.
data ImportOutcome
  = PlannedOnly [ImportPlan]
  | Imported [ImportResult]
  deriving stock (Show)

data ImportMode = DryRun | Execute
  deriving stock (Show, Eq)

data ImportOptions = ImportOptions
  { ioSince :: Maybe UTCTime
  , ioLimit :: Int
  , ioMode  :: ImportMode
  , ioForce :: Bool
  } deriving stock (Show)

-- | The Grocy object names an import run stocks into.
data SetupConfig = SetupConfig
  { scLocationName         :: Text
  , scShoppingLocationName :: Text
  , scQuantityUnitName     :: Text
  } deriving stock (Show, Eq)

data AppError
  = AppCookieError CookieError
  | AppWalmartError WalmartError
  | AppGrocyError GrocyError
  | AppStateCorrupt FilePath String
  deriving stock (Show, Eq)

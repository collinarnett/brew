module WalmartGrocy.Types
  ( Action (..)
  , ExecutedAction (..)
  , ImportPlan (..)
  , ImportResult (..)
  , SkippedOrder (..)
  , OrderFailure (..)
  , ImportOutcome (..)
  , ImportReport (..)
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

-- | An order whose details could not be fetched from Walmart; the
-- import continues without it.
data SkippedOrder = SkippedOrder
  { soOrderId :: OrderId
  , soError   :: WalmartError
  } deriving stock (Show)

-- | An order whose execution stopped partway: everything in ofStocked
-- reached Grocy before ofError hit, and ofNotExecuted (headed by the
-- failing item) did not.
data OrderFailure = OrderFailure
  { ofOrderId     :: OrderId
  , ofStocked     :: [ExecutedAction]
  , ofNotExecuted :: [Action]
  , ofError       :: GrocyError
  } deriving stock (Show)

-- | A dry run stops at the plans; only a real run has results and
-- failures to record in the state file.
data ImportOutcome
  = PlannedOnly [ImportPlan]
  | Imported [ImportResult] [OrderFailure]
  deriving stock (Show)

data ImportReport = ImportReport
  { reportSkipped :: [SkippedOrder]
  , reportOutcome :: ImportOutcome
  } deriving stock (Show)

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

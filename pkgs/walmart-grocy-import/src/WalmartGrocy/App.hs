{-# LANGUAGE OverloadedStrings #-}

module WalmartGrocy.App
  ( GrocySetup (..)
  , ensureSetup
  , runImport
  , runList
  , loadImportedOrders
  , saveImportedOrders
  ) where

import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT)
import Data.Aeson qualified as Aeson
import Data.Bifunctor (first)
import Data.ByteString.Lazy qualified as LBS
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Time (Day, UTCTime, utctDay)
import System.Directory (doesFileExist)
import System.IO (hPutStrLn, stderr)

import Grocy (GrocyError, LocationId, Product, QuantityUnitId, ShoppingLocationId)
import Grocy qualified
import Walmart qualified
import Walmart.Types (OrderId (..), OrderSummary (..), WalmartItem (..))
import WalmartGrocy.Reconcile (deduplicateBy, reconcile)
import WalmartGrocy.Types

-- | The resolved ids of the Grocy objects an import stocks into.
data GrocySetup = GrocySetup
  { gsLocation         :: LocationId
  , gsShoppingLocation :: ShoppingLocationId
  , gsQuantityUnit     :: QuantityUnitId
  } deriving stock (Show)

ensureSetup :: Grocy.Env -> SetupConfig -> IO (Either GrocyError GrocySetup)
ensureSetup grocy cfg = runExceptT $ GrocySetup
  <$> ExceptT (Grocy.ensureLocation grocy (scLocationName cfg))
  <*> ExceptT (Grocy.ensureShoppingLocation grocy (scShoppingLocationName cfg))
  <*> ExceptT (Grocy.findQuantityUnit grocy (scQuantityUnitName cfg))

loadImportedOrders :: FilePath -> IO (Either AppError (Set OrderId))
loadImportedOrders path = do
  exists <- doesFileExist path
  if not exists
    then pure (Right Set.empty)
    else do
      contents <- LBS.readFile path
      case Aeson.eitherDecode contents of
        Left err  -> pure (Left (AppStateCorrupt path err))
        Right ids -> pure (Right (Set.fromList (map OrderId ids)))

saveImportedOrders :: FilePath -> Set OrderId -> IO ()
saveImportedOrders path ids =
  LBS.writeFile path (Aeson.encode (map unOrderId (Set.toList ids)))

executePlan :: Grocy.Env -> GrocySetup -> ImportPlan -> IO (Either AppError ImportResult)
executePlan grocy setup plan = runExceptT $ do
  executed <- traverse
    (\a -> ExceptT $ first AppGrocyError <$> executeAction grocy setup (utctDay (ipOrderDate plan)) a)
    (ipActions plan)
  pure ImportResult
    { irOrderId = ipOrderId plan
    , irActions = executed
    }

executeAction :: Grocy.Env -> GrocySetup -> Day -> Action -> IO (Either GrocyError ExecutedAction)
executeAction grocy setup purchaseDate action = case action of
  CreateAndStock item -> runExceptT $ do
    created <- ExceptT $ Grocy.createProduct grocy Grocy.NewProduct
      { Grocy.newProductName             = wiName item
      , Grocy.newProductLocation         = gsLocation setup
      , Grocy.newProductQuantityUnit     = gsQuantityUnit setup
      , Grocy.newProductShoppingLocation = gsShoppingLocation setup
      }
    ExceptT $ stockItem grocy item created purchaseDate
    pure (Created item created)
  StockExisting item existing -> runExceptT $ do
    ExceptT $ stockItem grocy item existing purchaseDate
    pure (Stocked item existing)

stockItem :: Grocy.Env -> WalmartItem -> Product -> Day -> IO (Either GrocyError ())
stockItem grocy item product_ purchaseDate =
  Grocy.addStock grocy (Grocy.productId product_) Grocy.StockPurchase
    { Grocy.purchaseAmount     = wiQuantity item
    , Grocy.purchasePrice      = wiLinePrice item
    , Grocy.purchasedOn        = purchaseDate
    , Grocy.purchaseBestBefore = Grocy.neverExpires
    }

runImport
  :: Walmart.Env -> Grocy.Env -> SetupConfig -> FilePath -> ImportOptions
  -> IO (Either AppError ImportOutcome)
runImport walmart grocy setupCfg stateFile opts = runExceptT $ do
  products  <- ExceptT $ first AppGrocyError <$> Grocy.getProducts grocy
  imported  <- ExceptT $ loadImportedOrders stateFile
  summaries <- ExceptT $ first AppWalmartError <$>
    Walmart.getOrders walmart (ioSince opts) (ioLimit opts)

  let unique = deduplicateBy osOrderId summaries
      unimported
        | ioForce opts = unique
        | otherwise    = filter (\s -> not (Set.member (osOrderId s) imported)) unique

  orders <- lift $ traverseWithErrors
    (\s -> first AppWalmartError <$> Walmart.getOrder walmart s) unimported

  let plans = map (reconcile products) orders
  case ioMode opts of
    DryRun  -> pure (PlannedOnly plans)
    Execute -> do
      setup   <- ExceptT $ first AppGrocyError <$> ensureSetup grocy setupCfg
      results <- traverse (ExceptT . executePlan grocy setup) plans
      let newIds = Set.fromList (map irOrderId results)
      lift $ saveImportedOrders stateFile (Set.union imported newIds)
      pure (Imported results)

runList
  :: Walmart.Env -> Maybe UTCTime -> Int
  -> IO (Either AppError [OrderSummary])
runList walmart mSince limit =
  first AppWalmartError <$> Walmart.getOrders walmart mSince limit

-- | Fetch each order, warning on stderr and continuing when one fails;
-- a single unfetchable order should not abort the whole import.
traverseWithErrors :: (a -> IO (Either AppError b)) -> [a] -> IO [b]
traverseWithErrors f = go []
  where
    go acc [] = pure (reverse acc)
    go acc (x : xs) = do
      result <- f x
      case result of
        Right val -> go (val : acc) xs
        Left err  -> do
          hPutStrLn stderr ("  Skipping: " <> show err)
          go acc xs

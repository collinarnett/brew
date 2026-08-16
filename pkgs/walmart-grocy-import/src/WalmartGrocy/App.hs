{-# LANGUAGE OverloadedStrings #-}

module WalmartGrocy.App
  ( SetupConfig (..)
  , GrocySetup (..)
  , ensureSetup
  , runImport
  , runList
  , loadImportedOrders
  , saveImportedOrders
  ) where

import Control.Monad (when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT)
import Data.Aeson qualified as Aeson
import Data.Bifunctor (first)
import Data.ByteString.Lazy qualified as LBS
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Time (UTCTime, utctDay)
import System.Directory (doesFileExist)
import System.IO (hPutStrLn, stderr)

import Grocy (GrocyError, LocationId, Product, QuantityUnitId, ShoppingLocationId)
import Grocy qualified
import Walmart qualified
import Walmart.Types (OrderId (..), OrderSummary (..), WalmartItem (..))
import WalmartGrocy.Reconcile (deduplicateBy, reconcile)
import WalmartGrocy.Types

-- | The Grocy object names an import run stocks into.
data SetupConfig = SetupConfig
  { scLocationName         :: Text
  , scShoppingLocationName :: Text
  , scQuantityUnitName     :: Text
  } deriving stock (Show)

-- | The resolved ids of those objects.
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

loadImportedOrders :: FilePath -> IO (Set OrderId)
loadImportedOrders path = do
  exists <- doesFileExist path
  if not exists
    then pure Set.empty
    else do
      contents <- LBS.readFile path
      case Aeson.eitherDecode contents of
        Left _    -> pure Set.empty
        Right ids -> pure (Set.fromList (map OrderId ids))

saveImportedOrders :: FilePath -> Set OrderId -> IO ()
saveImportedOrders path ids =
  LBS.writeFile path (Aeson.encode (map unOrderId (Set.toList ids)))

executePlan
  :: Grocy.Env -> GrocySetup -> UTCTime -> Bool -> ImportPlan
  -> IO (Either AppError ImportResult)
executePlan grocy setup orderDate dryRun plan = runExceptT $ do
  results <- traverse
    (\a -> ExceptT $ first AppGrocyError <$> executeAction grocy setup dryRun orderDate a)
    (ipActions plan)
  pure ImportResult
    { irOrderId = ipOrderId plan
    , irMatched = [(i, p) | (StockExisting i p, _) <- results]
    , irCreated = [(i, p) | (CreateAndStock i, Just p) <- results]
    }

executeAction
  :: Grocy.Env -> GrocySetup -> Bool -> UTCTime -> Action
  -> IO (Either GrocyError (Action, Maybe Product))
executeAction grocy setup dryRun orderDate action = case action of
  CreateAndStock item
    | dryRun    -> pure (Right (action, Nothing))
    | otherwise -> runExceptT $ do
        created <- ExceptT $ Grocy.createProduct grocy Grocy.NewProduct
          { Grocy.newProductName             = wiName item
          , Grocy.newProductLocation         = gsLocation setup
          , Grocy.newProductQuantityUnit     = gsQuantityUnit setup
          , Grocy.newProductShoppingLocation = gsShoppingLocation setup
          }
        ExceptT $ stockItem grocy item created orderDate
        pure (action, Just created)
  StockExisting item existing
    | dryRun    -> pure (Right (action, Nothing))
    | otherwise -> runExceptT $ do
        ExceptT $ stockItem grocy item existing orderDate
        pure (action, Nothing)

stockItem :: Grocy.Env -> WalmartItem -> Product -> UTCTime -> IO (Either GrocyError ())
stockItem grocy item product_ orderDate =
  Grocy.addStock grocy (Grocy.productId product_) Grocy.StockPurchase
    { Grocy.purchaseAmount     = wiQuantity item
    , Grocy.purchasePrice      = wiLinePrice item
    , Grocy.purchasedOn        = utctDay orderDate
    , Grocy.purchaseBestBefore = Grocy.neverExpires
    }

runImport
  :: Walmart.Env -> Grocy.Env -> SetupConfig -> FilePath
  -> Verbosity -> ImportOptions
  -> IO (Either AppError [ImportResult])
runImport walmart grocy setupCfg stateFile verbosity opts = runExceptT $ do
  setup      <- ExceptT $ first AppGrocyError <$> ensureSetup grocy setupCfg
  products   <- ExceptT $ first AppGrocyError <$> Grocy.getProducts grocy
  imported   <- lift $ loadImportedOrders stateFile
  summaries  <- ExceptT $ first AppWalmartError <$>
    Walmart.getOrders walmart (ioSince opts) (ioLimit opts)

  let unique = deduplicateBy osOrderId summaries
      unimported
        | ioForce opts = unique
        | otherwise    = filter (\s -> not (Set.member (osOrderId s) imported)) unique

  orders <- lift $ traverseWithErrors verbosity
    (\s -> first AppWalmartError <$> Walmart.getOrder walmart s) unimported

  let plans = map (reconcile products) orders
  results <- traverse
    (\p -> ExceptT $ executePlan grocy setup (ipOrderDate p) (ioDryRun opts) p)
    plans

  when (not (ioDryRun opts)) $ lift $ do
    let newIds = Set.fromList (map irOrderId results)
    saveImportedOrders stateFile (Set.union imported newIds)

  pure results

runList
  :: Walmart.Env -> Maybe UTCTime -> Int
  -> IO (Either AppError [OrderSummary])
runList walmart mSince limit =
  first AppWalmartError <$> Walmart.getOrders walmart mSince limit

traverseWithErrors :: Verbosity -> (a -> IO (Either AppError b)) -> [a] -> IO [b]
traverseWithErrors verbosity f = go []
  where
    go acc [] = pure (reverse acc)
    go acc (x : xs) = do
      result <- f x
      case result of
        Right val -> go (val : acc) xs
        Left err  -> do
          when (verbosity >= Normal) $
            hPutStrLn stderr ("  Skipping: " <> show err)
          go acc xs

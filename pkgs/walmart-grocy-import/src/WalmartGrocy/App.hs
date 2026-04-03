{-# LANGUAGE OverloadedStrings #-}

-- | Application pipeline — composes IO adapters with pure reconciliation.
module WalmartGrocy.App
  ( runImport
  , runList
  , loadImportedOrders
  , saveImportedOrders
  ) where

import Control.Exception (SomeException, try)
import Control.Monad (when)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Time (UTCTime)
import Network.HTTP.Client (CookieJar, Manager)
import System.Directory (doesFileExist)
import System.IO (hPutStrLn, stderr)

import WalmartGrocy.Extractor (resolveEndpoints)
import WalmartGrocy.Grocy
import WalmartGrocy.Reconcile (deduplicateBy, reconcile)
import WalmartGrocy.Types
import WalmartGrocy.Walmart (walmartGetHistory, walmartGetOrder)

-- | Load previously imported order IDs from disk.
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

-- | Save imported order IDs to disk.
saveImportedOrders :: FilePath -> Set OrderId -> IO ()
saveImportedOrders path ids =
  LBS.writeFile path (Aeson.encode (map unOrderId (Set.toList ids)))

-- | Execute a reconciliation plan against Grocy.
executePlan :: GrocyEnv -> GrocySetup -> UTCTime -> Bool -> ImportPlan -> IO ImportResult
executePlan env setup orderDate dryRun plan = do
  results <- traverse (executeAction env setup dryRun orderDate) (ipActions plan)
  pure ImportResult
    { irOrderId = ipOrderId plan
    , irMatched = [(i, p) | (StockExisting i p, _) <- results]
    , irCreated = [(i, p) | (CreateAndStock i, Just p) <- results]
    }

executeAction
  :: GrocyEnv -> GrocySetup -> Bool -> UTCTime -> Action
  -> IO (Action, Maybe GrocyProduct)
executeAction env setup dryRun orderDate action = case action of
  CreateAndStock item
    | dryRun    -> pure (action, Nothing)
    | otherwise -> do
        gp <- grocyCreateProduct env setup (wiName item)
        grocyAddStock env gp (wiQuantity item) (wiLinePrice item) orderDate
        pure (action, Just gp)
  StockExisting item gp
    | dryRun    -> pure (action, Nothing)
    | otherwise -> do
        grocyAddStock env gp (wiQuantity item) (wiLinePrice item) orderDate
        pure (action, Nothing)

-- | Full import pipeline.
runImport
  :: Manager -> CookieJar -> GrocyEnv -> FilePath -> FilePath
  -> Verbosity -> ImportOptions
  -> IO [ImportResult]
runImport mgr cookies grocyEnv cacheDir stateFile verbosity opts = do
  endpoints  <- resolveEndpoints mgr cacheDir
  setup      <- grocyEnsureSetup grocyEnv
  products   <- grocyGetProducts grocyEnv
  imported   <- loadImportedOrders stateFile
  summaries  <- walmartGetHistory mgr cookies endpoints (ioSince opts) (ioLimit opts)

  let unique = deduplicateBy osOrderId summaries
      unimported
        | ioForce opts = unique
        | otherwise    = filter (\s -> not (Set.member (osOrderId s) imported)) unique

  orders <- traverseWithErrors verbosity
    (\s -> walmartGetOrder mgr cookies endpoints s) unimported

  let plans = map (reconcile products) orders
  results <- traverse
    (\p -> executePlan grocyEnv setup (ipOrderDate p) (ioDryRun opts) p)
    plans

  -- Mark successfully imported orders
  when (not (ioDryRun opts)) $ do
    let newIds = Set.fromList (map irOrderId results)
    saveImportedOrders stateFile (Set.union imported newIds)

  pure results

-- | List recent orders.
runList :: Manager -> CookieJar -> FilePath -> Maybe UTCTime -> Int -> IO [OrderSummary]
runList mgr cookies cacheDir mSince limit = do
  endpoints <- resolveEndpoints mgr cacheDir
  walmartGetHistory mgr cookies endpoints mSince limit

-- | Traverse that logs and skips failures instead of aborting.
traverseWithErrors :: Verbosity -> (a -> IO b) -> [a] -> IO [b]
traverseWithErrors verbosity f = go []
  where
    go acc [] = pure (reverse acc)
    go acc (x : xs) = do
      result <- try @SomeException (f x)
      case result of
        Right val -> go (val : acc) xs
        Left err  -> do
          when (verbosity >= Normal) $
            hPutStrLn stderr ("  Skipping: " <> show err)
          go acc xs

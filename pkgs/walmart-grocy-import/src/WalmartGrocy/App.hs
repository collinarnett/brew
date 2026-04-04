{-# LANGUAGE OverloadedStrings #-}

module WalmartGrocy.App
  ( runImport
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
import Data.Time (UTCTime)
import System.Directory (doesFileExist)
import System.IO (hPutStrLn, stderr)

import Walmart qualified
import Walmart.Types (OrderId (..), OrderSummary (..), WalmartItem (..))
import WalmartGrocy.Grocy qualified as Grocy
import WalmartGrocy.Grocy (GrocyConfig, GrocySetup, SetupConfig)
import WalmartGrocy.Reconcile (deduplicateBy, reconcile)
import WalmartGrocy.Types

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
  :: GrocyConfig -> GrocySetup -> UTCTime -> Bool -> ImportPlan
  -> IO (Either AppError ImportResult)
executePlan gc setup orderDate dryRun plan = runExceptT $ do
  results <- traverse
    (\a -> ExceptT $ first AppGrocyError <$> executeAction gc setup dryRun orderDate a)
    (ipActions plan)
  pure ImportResult
    { irOrderId = ipOrderId plan
    , irMatched = [(i, (pid, n)) | (StockExisting i (pid, n), _) <- results]
    , irCreated = [(i, (pid, n)) | (CreateAndStock i, Just (pid, n)) <- results]
    }

executeAction
  :: GrocyConfig -> GrocySetup -> Bool -> UTCTime -> Action
  -> IO (Either Grocy.GrocyError (Action, Maybe (Int, Text)))
executeAction gc setup dryRun orderDate action = case action of
  CreateAndStock item
    | dryRun    -> pure (Right (action, Nothing))
    | otherwise -> do
        result <- Grocy.createProduct gc setup (wiName item)
        case result of
          Left err -> pure (Left err)
          Right (pid, name) -> do
            stockResult <- Grocy.addStock gc pid (wiQuantity item) (wiLinePrice item) orderDate
            case stockResult of
              Left err -> pure (Left err)
              Right () -> pure (Right (action, Just (pid, name)))
  StockExisting item (pid, _)
    | dryRun    -> pure (Right (action, Nothing))
    | otherwise -> do
        result <- Grocy.addStock gc pid (wiQuantity item) (wiLinePrice item) orderDate
        case result of
          Left err -> pure (Left err)
          Right () -> pure (Right (action, Nothing))

runImport
  :: Walmart.Env -> GrocyConfig -> SetupConfig -> FilePath
  -> Verbosity -> ImportOptions
  -> IO (Either AppError [ImportResult])
runImport walmartEnv gc setupCfg stateFile verbosity opts = runExceptT $ do
  setup      <- ExceptT $ first AppGrocyError <$> Grocy.ensureSetup gc setupCfg
  products   <- ExceptT $ first AppGrocyError <$> Grocy.getProducts gc
  imported   <- lift $ loadImportedOrders stateFile
  summaries  <- ExceptT $ first AppWalmartError <$>
    Walmart.getOrders walmartEnv (ioSince opts) (ioLimit opts)

  let unique = deduplicateBy osOrderId summaries
      unimported
        | ioForce opts = unique
        | otherwise    = filter (\s -> not (Set.member (osOrderId s) imported)) unique

  orders <- lift $ traverseWithErrors verbosity
    (\s -> first AppWalmartError <$> Walmart.getOrder walmartEnv s) unimported

  let plans = map (reconcile products) orders
  results <- traverse
    (\p -> ExceptT $ executePlan gc setup (ipOrderDate p) (ioDryRun opts) p)
    plans

  when (not (ioDryRun opts)) $ lift $ do
    let newIds = Set.fromList (map irOrderId results)
    saveImportedOrders stateFile (Set.union imported newIds)

  pure results

runList
  :: Walmart.Env -> Maybe UTCTime -> Int
  -> IO (Either AppError [OrderSummary])
runList walmartEnv mSince limit =
  first AppWalmartError <$> Walmart.getOrders walmartEnv mSince limit

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

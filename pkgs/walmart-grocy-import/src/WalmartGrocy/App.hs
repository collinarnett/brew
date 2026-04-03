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
import Data.Time (UTCTime)
import System.Directory (doesFileExist)
import System.IO (hPutStrLn, stderr)

import Grocy qualified
import Grocy.Types (GrocyError, GrocyProduct (..), GrocySetup, SetupConfig)
import Grocy.Types qualified
import Walmart qualified
import Walmart.Types (OrderId (..), OrderSummary (..), WalmartItem (..))
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
  :: Grocy.Types.Env -> GrocySetup -> UTCTime -> Bool -> ImportPlan
  -> IO (Either AppError ImportResult)
executePlan env setup orderDate dryRun plan = runExceptT $ do
  results <- traverse
    (\a -> ExceptT $ first AppGrocyError <$> executeAction env setup dryRun orderDate a)
    (ipActions plan)
  pure ImportResult
    { irOrderId = ipOrderId plan
    , irMatched = [(i, p) | (StockExisting i p, _) <- results]
    , irCreated = [(i, p) | (CreateAndStock i, Just p) <- results]
    }

executeAction
  :: Grocy.Types.Env -> GrocySetup -> Bool -> UTCTime -> Action
  -> IO (Either GrocyError (Action, Maybe GrocyProduct))
executeAction env setup dryRun orderDate action = case action of
  CreateAndStock item
    | dryRun    -> pure (Right (action, Nothing))
    | otherwise -> runExceptT $ do
        gp <- ExceptT $ Grocy.createProduct env setup (wiName item)
        ExceptT $ Grocy.addStock env gp (wiQuantity item) (wiLinePrice item) orderDate
        pure (action, Just gp)
  StockExisting item gp
    | dryRun    -> pure (Right (action, Nothing))
    | otherwise -> runExceptT $ do
        ExceptT $ Grocy.addStock env gp (wiQuantity item) (wiLinePrice item) orderDate
        pure (action, Nothing)

runImport
  :: Walmart.Env -> Grocy.Types.Env -> SetupConfig -> FilePath
  -> Verbosity -> ImportOptions
  -> IO (Either AppError [ImportResult])
runImport walmartEnv grocyEnv setupCfg stateFile verbosity opts = runExceptT $ do
  setup      <- ExceptT $ first AppGrocyError <$> Grocy.ensureSetup grocyEnv setupCfg
  products   <- ExceptT $ first AppGrocyError <$> Grocy.getProducts grocyEnv
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
    (\p -> ExceptT $ executePlan grocyEnv setup (ipOrderDate p) (ioDryRun opts) p)
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

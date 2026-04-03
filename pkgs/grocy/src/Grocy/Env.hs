{-# LANGUAGE OverloadedStrings #-}

module Grocy.Env
  ( newEnv
  , getProducts
  , createProduct
  , addStock
  , ensureSetup
  ) where

import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import Data.Aeson qualified as Aeson
import Data.Aeson.Types (parseMaybe)
import Data.Maybe (mapMaybe)
import Data.Scientific (Scientific, scientific)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import Money (Discrete)
import Network.HTTP.Client (newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Text.Read (readMaybe)

import Grocy.Internal.HTTP (grocyGet, grocyPost)
import Grocy.Internal.JSON (parseGrocyProducts)
import Grocy.Types

newEnv :: Text -> Text -> IO Env
newEnv baseUrl apiKey = do
  mgr <- newManager tlsManagerSettings
  pure Env { envBaseUrl = baseUrl, envApiKey = apiKey, envManager = mgr }

getProducts :: Env -> IO (Either GrocyError [GrocyProduct])
getProducts env = runExceptT $ do
  body <- ExceptT $ grocyGet env "/api/objects/products"
  case Aeson.eitherDecode body of
    Left err  -> throwE (GrocyDecodeError err)
    Right val -> case parseGrocyProducts val of
      Left err -> throwE (GrocyParseError err)
      Right ps -> pure ps

createProduct :: Env -> GrocySetup -> Text -> IO (Either GrocyError GrocyProduct)
createProduct env setup name = runExceptT $ do
  let payload = Aeson.object
        [ "name"            Aeson..= name
        , "location_id"     Aeson..= gsLocationId setup
        , "qu_id_purchase"  Aeson..= gsPieceUnitId setup
        , "qu_id_stock"     Aeson..= gsPieceUnitId setup
        , "shopping_location_id" Aeson..= gsShoppingLocationId setup
        ]
  body <- lift $ grocyPost env "/api/objects/products" payload
  case Aeson.eitherDecode body of
    Left _ -> ExceptT $ findProductByName env name
    Right obj -> case parseMaybe (Aeson..: "created_object_id") obj of
      Just idStr -> case readMaybe (T.unpack idStr) of
        Just pid -> pure GrocyProduct { gpId = ProductId pid, gpName = name }
        Nothing  -> throwE (GrocyIdParseError (T.unpack idStr))
      Nothing -> ExceptT $ findProductByName env name

findProductByName :: Env -> Text -> IO (Either GrocyError GrocyProduct)
findProductByName env name = runExceptT $ do
  products <- ExceptT $ getProducts env
  case filter (\p -> gpName p == name) products of
    (p : _) -> pure p
    []      -> throwE (GrocyProductNotFound name)

addStock
  :: Env
  -> GrocyProduct
  -> Scientific
  -> Maybe (Discrete "USD" "cent")
  -> UTCTime
  -> IO (Either GrocyError ())
addStock env gp quantity mPrice purchaseDate = runExceptT $ do
  let ProductId pid = gpId gp
      payload = Aeson.object $
        [ "amount"           Aeson..= quantity
        , "transaction_type" Aeson..= ("purchase" :: Text)
        , "best_before_date" Aeson..= ("2999-12-31" :: Text)
        , "purchased_date"   Aeson..= T.pack (take 10 (iso8601Show purchaseDate))
        ]
        <> maybe [] (\p -> ["price" Aeson..= discreteToScientific p]) mPrice
  _ <- lift $ grocyPost env ("/api/stock/products/" <> T.pack (show pid) <> "/add") payload
  pure ()

ensureSetup :: Env -> SetupConfig -> IO (Either GrocyError GrocySetup)
ensureSetup env cfg = runExceptT $ do
  locationId  <- ExceptT $ ensureEntity env "locations" (scLocationName cfg)
  shoppingId  <- ExceptT $ ensureEntity env "shopping_locations" (scShoppingLocationName cfg)
  unitId      <- ExceptT $ findEntity env "quantity_units" (scQuantityUnitName cfg)
  pure GrocySetup
    { gsLocationId         = locationId
    , gsShoppingLocationId = shoppingId
    , gsPieceUnitId        = unitId
    }

-- Internal helpers

discreteToScientific :: Discrete "USD" "cent" -> Scientific
discreteToScientific d = scientific (toInteger d) (-2)

ensureEntity :: Env -> Text -> Text -> IO (Either GrocyError Int)
ensureEntity env entityType name = do
  existing <- findEntityMaybe env entityType name
  case existing of
    Right (Just eid) -> pure (Right eid)
    Right Nothing    -> createEntity env entityType name
    Left err         -> pure (Left err)

findEntity :: Env -> Text -> Text -> IO (Either GrocyError Int)
findEntity env entityType name = do
  existing <- findEntityMaybe env entityType name
  case existing of
    Right (Just eid) -> pure (Right eid)
    Right Nothing    -> pure (Left (GrocyEntityNotFound entityType name))
    Left err         -> pure (Left err)

findEntityMaybe :: Env -> Text -> Text -> IO (Either GrocyError (Maybe Int))
findEntityMaybe env entityType name = do
  result <- grocyGet env ("/api/objects/" <> entityType)
  case result of
    Left err   -> pure (Left err)
    Right body -> case Aeson.eitherDecode body of
      Left _   -> pure (Right Nothing)
      Right arr -> pure (Right (findByName name arr))

findByName :: Text -> [Aeson.Value] -> Maybe Int
findByName target items =
  case mapMaybe extractMatch items of
    (eid : _) -> Just eid
    []        -> Nothing
  where
    extractMatch (Aeson.Object obj) = do
      name <- parseMaybe (Aeson..: "name") obj
      eid  <- parseMaybe (Aeson..: "id") obj
      if name == target then Just eid else Nothing
    extractMatch _ = Nothing

createEntity :: Env -> Text -> Text -> IO (Either GrocyError Int)
createEntity env entityType name = runExceptT $ do
  let payload = Aeson.object ["name" Aeson..= name]
  body <- lift $ grocyPost env ("/api/objects/" <> entityType) payload
  case Aeson.eitherDecode body of
    Left err -> throwE (GrocyCreateError entityType err)
    Right obj -> case parseMaybe (Aeson..: "created_object_id") obj of
      Just idStr -> case readMaybe (T.unpack idStr) of
        Just eid -> pure eid
        Nothing  -> throwE (GrocyIdParseError (T.unpack idStr))
      Nothing -> throwE (GrocyMissingId entityType)

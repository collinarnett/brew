{-# LANGUAGE OverloadedStrings #-}

-- | Grocy REST API client.
module WalmartGrocy.Grocy
  ( grocyGetProducts
  , grocyCreateProduct
  , grocyAddStock
  , grocyEnsureSetup
  , GrocySetup (..)
  ) where

import Data.Aeson qualified as Aeson
import Data.Aeson.Types (parseMaybe)
import Data.ByteString.Lazy qualified as LBS
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (UTCTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import Network.HTTP.Client
import Network.HTTP.Types.Status (statusCode)

import WalmartGrocy.JSON (parseGrocyProducts)
import WalmartGrocy.Types

-- | IDs resolved during setup, used for product creation.
data GrocySetup = GrocySetup
  { gsLocationId        :: Int  -- ^ Pantry location
  , gsShoppingLocationId :: Int  -- ^ Walmart shopping location
  , gsPieceUnitId       :: Int  -- ^ Piece quantity unit
  } deriving stock (Show)

-- | Fetch all products from Grocy.
grocyGetProducts :: GrocyEnv -> IO [GrocyProduct]
grocyGetProducts env = do
  body <- grocyGet env "/api/objects/products"
  case Aeson.eitherDecode body of
    Left err  -> fail ("Failed to decode Grocy products JSON: " <> err)
    Right val -> case parseGrocyProducts val of
      Left err -> fail ("Failed to parse Grocy products: " <> err)
      Right ps -> pure ps

-- | Create a new product in Grocy, or return the existing one if
-- a product with the same name already exists.
grocyCreateProduct :: GrocyEnv -> GrocySetup -> Text -> IO GrocyProduct
grocyCreateProduct env setup name = do
  let payload = Aeson.object
        [ "name"            Aeson..= name
        , "location_id"     Aeson..= gsLocationId setup
        , "qu_id_purchase"  Aeson..= gsPieceUnitId setup
        , "qu_id_stock"     Aeson..= gsPieceUnitId setup
        , "shopping_location_id" Aeson..= gsShoppingLocationId setup
        ]
  body <- grocyPost env "/api/objects/products" payload
  case Aeson.eitherDecode body of
    Left _ -> findProductByName env name
    Right obj -> case parseMaybe (Aeson..: "created_object_id") obj of
      Just idStr -> pure GrocyProduct
        { gpId = ProductId (read (T.unpack idStr))
        , gpName = name
        }
      Nothing -> findProductByName env name

-- | Look up a product by exact name match.
findProductByName :: GrocyEnv -> Text -> IO GrocyProduct
findProductByName env name = do
  products <- grocyGetProducts env
  case filter (\p -> gpName p == name) products of
    (p : _) -> pure p
    []      -> fail ("Product not found and could not be created: " <> T.unpack name)

-- | Add stock to an existing product.
-- | Add stock to an existing product.
grocyAddStock
  :: GrocyEnv
  -> GrocyProduct    -- ^ product
  -> Scientific      -- ^ quantity
  -> Maybe Scientific -- ^ price
  -> UTCTime         -- ^ purchase date
  -> IO ()
grocyAddStock env gp quantity mPrice purchaseDate = do
  let ProductId pid = gpId gp
      payload = Aeson.object $
        [ "amount"           Aeson..= quantity
        , "transaction_type" Aeson..= ("purchase" :: Text)
        , "best_before_date" Aeson..= ("2999-12-31" :: Text)
        , "purchased_date"   Aeson..= T.pack (take 10 (iso8601Show purchaseDate))
        ]
        <> maybe [] (\p -> ["price" Aeson..= p]) mPrice
  _ <- grocyPost env ("/api/stock/products/" <> T.pack (show pid) <> "/add") payload
  pure ()

-- | Ensure required Grocy entities exist (locations, shopping locations).
-- Idempotent — checks for existing entities before creating.
grocyEnsureSetup :: GrocyEnv -> IO GrocySetup
grocyEnsureSetup env = do
  pantryId   <- ensureEntity env "locations" "Pantry"
  walmartId  <- ensureEntity env "shopping_locations" "Walmart"
  pieceId    <- findEntity env "quantity_units" "Piece"
  pure GrocySetup
    { gsLocationId         = pantryId
    , gsShoppingLocationId = walmartId
    , gsPieceUnitId        = pieceId
    }

-- Internal helpers

ensureEntity :: GrocyEnv -> Text -> Text -> IO Int
ensureEntity env entityType name = do
  existing <- findEntityMaybe env entityType name
  case existing of
    Just eid -> pure eid
    Nothing  -> createEntity env entityType name

findEntity :: GrocyEnv -> Text -> Text -> IO Int
findEntity env entityType name = do
  existing <- findEntityMaybe env entityType name
  case existing of
    Just eid -> pure eid
    Nothing  -> fail ("Required Grocy entity not found: " <> T.unpack entityType <> "/" <> T.unpack name)

findEntityMaybe :: GrocyEnv -> Text -> Text -> IO (Maybe Int)
findEntityMaybe env entityType name = do
  body <- grocyGet env ("/api/objects/" <> entityType)
  case Aeson.eitherDecode body of
    Left _ -> pure Nothing
    Right arr -> pure $ findByName name arr

findByName :: Text -> [Aeson.Value] -> Maybe Int
findByName target = foldr check Nothing
  where
    check _ acc@(Just _) = acc
    check (Aeson.Object obj) Nothing = do
      name <- parseMaybe (Aeson..: "name") obj
      eid  <- parseMaybe (Aeson..: "id") obj
      if name == target then Just eid else Nothing
    check _ Nothing = Nothing

createEntity :: GrocyEnv -> Text -> Text -> IO Int
createEntity env entityType name = do
  let payload = Aeson.object ["name" Aeson..= name]
  body <- grocyPost env ("/api/objects/" <> entityType) payload
  case Aeson.eitherDecode body of
    Left err -> fail ("Failed to create " <> T.unpack entityType <> ": " <> err)
    Right obj -> case parseMaybe (Aeson..: "created_object_id") obj of
      Just idStr -> pure (read (T.unpack idStr))
      Nothing -> fail ("No created_object_id in " <> T.unpack entityType <> " response")

grocyGet :: GrocyEnv -> Text -> IO LBS.ByteString
grocyGet env path = do
  let url = T.unpack (geBaseUrl env <> path)
  req <- parseRequest url
  let req' = req
        { method = "GET"
        , requestHeaders =
            [ ("GROCY-API-KEY", TE.encodeUtf8 (geApiKey env))
            , ("Accept", "application/json")
            ]
        }
  resp <- httpLbs req' (geManager env)
  let code = statusCode (responseStatus resp)
  if code == 200
    then pure (responseBody resp)
    else fail ("Grocy GET " <> T.unpack path <> " returned HTTP " <> show code)

grocyPost :: GrocyEnv -> Text -> Aeson.Value -> IO LBS.ByteString
grocyPost env path payload = do
  let url = T.unpack (geBaseUrl env <> path)
  req <- parseRequest url
  let req' = req
        { method = "POST"
        , requestHeaders =
            [ ("GROCY-API-KEY", TE.encodeUtf8 (geApiKey env))
            , ("Content-Type", "application/json")
            , ("Accept", "application/json")
            ]
        , requestBody = RequestBodyLBS (Aeson.encode payload)
        }
  resp <- httpLbs req' (geManager env)
  pure (responseBody resp)

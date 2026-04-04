{-# LANGUAGE OverloadedStrings #-}

-- | Grocy operations using the generated grocy-client.
module WalmartGrocy.Grocy
  ( GrocyConfig (..)
  , GrocySetup (..)
  , SetupConfig (..)
  , GrocyError (..)
  , getProducts
  , createProduct
  , addStock
  , ensureSetup
  ) where

import Data.Aeson qualified as Aeson
import Data.Aeson.Types (parseMaybe)
import Data.ByteString qualified as BS
import Data.Scientific (Scientific, scientific)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import GrocyClient.Common qualified as GC
import GrocyClient.Configuration (defaultConfiguration)
import GrocyClient.SecuritySchemes (apiKeyInHeaderAuthenticationSecurityScheme)
import Money (Discrete)
import Network.HTTP.Client (Response (..))
import Network.HTTP.Types.Status (statusCode)
import Text.Read (readMaybe)

data GrocyConfig = GrocyConfig
  { gcBaseUrl :: Text
  , gcApiKey  :: Text
  } deriving stock (Show)

data GrocySetup = GrocySetup
  { gsLocationId         :: Int
  , gsShoppingLocationId :: Int
  , gsPieceUnitId        :: Int
  } deriving stock (Show)

data SetupConfig = SetupConfig
  { scLocationName         :: Text
  , scShoppingLocationName :: Text
  , scQuantityUnitName     :: Text
  } deriving stock (Show)

data GrocyError
  = GrocyHttpError Text Int
  | GrocyParseError Text
  | GrocyEntityNotFound Text Text
  | GrocyProductNotFound Text
  | GrocyCreateError Text String
  deriving stock (Show, Eq)

toConfig :: GrocyConfig -> GC.Configuration
toConfig gc = defaultConfiguration
  { GC.configBaseURL = gcBaseUrl gc
  , GC.configSecurityScheme = apiKeyInHeaderAuthenticationSecurityScheme (gcApiKey gc)
  }

grocyGet :: GrocyConfig -> Text -> IO (Response BS.ByteString)
grocyGet gc path = GC.doCallWithConfiguration (toConfig gc) "GET" path []

grocyPost :: GrocyConfig -> Text -> Aeson.Value -> IO (Response BS.ByteString)
grocyPost gc path body = GC.doBodyCallWithConfiguration (toConfig gc) "POST" path [] (Just body) GC.RequestBodyEncodingJSON

getProducts :: GrocyConfig -> IO (Either GrocyError [(Int, Text)])
getProducts gc = do
  resp <- grocyGet gc "/api/objects/products"
  let code = statusCode (responseStatus resp)
  if code == 200
    then case Aeson.eitherDecodeStrict (responseBody resp) of
      Left err -> pure (Left (GrocyParseError (T.pack err)))
      Right vals -> pure (Right (parseProducts vals))
    else pure (Left (GrocyHttpError "/api/objects/products" code))

parseProducts :: [Aeson.Value] -> [(Int, Text)]
parseProducts = concatMap extract
  where
    extract (Aeson.Object obj) =
      case (,) <$> parseMaybe (Aeson..: "id") obj <*> parseMaybe (Aeson..: "name") obj of
        Just pair -> [pair]
        Nothing   -> []
    extract _ = []

createProduct :: GrocyConfig -> GrocySetup -> Text -> IO (Either GrocyError (Int, Text))
createProduct gc setup name = do
  let payload = Aeson.object
        [ "name"            Aeson..= name
        , "location_id"     Aeson..= gsLocationId setup
        , "qu_id_purchase"  Aeson..= gsPieceUnitId setup
        , "qu_id_stock"     Aeson..= gsPieceUnitId setup
        , "shopping_location_id" Aeson..= gsShoppingLocationId setup
        ]
  resp <- grocyPost gc "/api/objects/products" payload
  case Aeson.eitherDecodeStrict (responseBody resp) of
    Right obj | Just idStr <- parseMaybe (Aeson..: "created_object_id") obj ->
      case readMaybe (T.unpack idStr) of
        Just pid -> pure (Right (pid, name))
        Nothing  -> findProductByName gc name
    _ -> findProductByName gc name

findProductByName :: GrocyConfig -> Text -> IO (Either GrocyError (Int, Text))
findProductByName gc name = do
  result <- getProducts gc
  case result of
    Left err -> pure (Left err)
    Right products -> case filter (\(_, n) -> n == name) products of
      (p : _) -> pure (Right p)
      []      -> pure (Left (GrocyProductNotFound name))

addStock :: GrocyConfig -> Int -> Scientific -> Maybe (Discrete "USD" "cent") -> UTCTime -> IO (Either GrocyError ())
addStock gc productId quantity mPrice purchaseDate = do
  let path = "/api/stock/products/" <> T.pack (show productId) <> "/add"
      payload = Aeson.object $
        [ "amount"           Aeson..= quantity
        , "transaction_type" Aeson..= ("purchase" :: Text)
        , "best_before_date" Aeson..= ("2999-12-31" :: Text)
        , "purchased_date"   Aeson..= T.pack (take 10 (iso8601Show purchaseDate))
        ]
        <> maybe [] (\p -> ["price" Aeson..= discreteToScientific p]) mPrice
  resp <- grocyPost gc path payload
  let code = statusCode (responseStatus resp)
  if code == 200
    then pure (Right ())
    else pure (Left (GrocyHttpError path code))

ensureSetup :: GrocyConfig -> SetupConfig -> IO (Either GrocyError GrocySetup)
ensureSetup gc cfg = do
  loc <- ensureEntity gc "locations" (scLocationName cfg)
  case loc of
    Left err -> pure (Left err)
    Right locId -> do
      shop <- ensureEntity gc "shopping_locations" (scShoppingLocationName cfg)
      case shop of
        Left err -> pure (Left err)
        Right shopId -> do
          unit <- findEntity gc "quantity_units" (scQuantityUnitName cfg)
          case unit of
            Left err     -> pure (Left err)
            Right unitId -> pure (Right GrocySetup
              { gsLocationId = locId, gsShoppingLocationId = shopId, gsPieceUnitId = unitId })

ensureEntity :: GrocyConfig -> Text -> Text -> IO (Either GrocyError Int)
ensureEntity gc entityType name = do
  existing <- findEntityMaybe gc entityType name
  case existing of
    Left err         -> pure (Left err)
    Right (Just eid) -> pure (Right eid)
    Right Nothing    -> createEntity gc entityType name

findEntity :: GrocyConfig -> Text -> Text -> IO (Either GrocyError Int)
findEntity gc entityType name = do
  existing <- findEntityMaybe gc entityType name
  case existing of
    Left err         -> pure (Left err)
    Right (Just eid) -> pure (Right eid)
    Right Nothing    -> pure (Left (GrocyEntityNotFound entityType name))

findEntityMaybe :: GrocyConfig -> Text -> Text -> IO (Either GrocyError (Maybe Int))
findEntityMaybe gc entityType name = do
  resp <- grocyGet gc ("/api/objects/" <> entityType)
  let code = statusCode (responseStatus resp)
  if code == 200
    then case Aeson.eitherDecodeStrict (responseBody resp) of
      Left _    -> pure (Right Nothing)
      Right arr -> pure (Right (findByName name arr))
    else pure (Left (GrocyHttpError ("/api/objects/" <> entityType) code))

findByName :: Text -> [Aeson.Value] -> Maybe Int
findByName target = foldr check Nothing
  where
    check (Aeson.Object obj) Nothing = do
      n   <- parseMaybe (Aeson..: "name") obj
      eid <- parseMaybe (Aeson..: "id") obj
      if n == target then Just eid else Nothing
    check _ acc = acc

createEntity :: GrocyConfig -> Text -> Text -> IO (Either GrocyError Int)
createEntity gc entityType name = do
  let payload = Aeson.object ["name" Aeson..= name]
  resp <- grocyPost gc ("/api/objects/" <> entityType) payload
  case Aeson.eitherDecodeStrict (responseBody resp) of
    Left err -> pure (Left (GrocyCreateError entityType err))
    Right obj -> case parseMaybe (Aeson..: "created_object_id") obj of
      Just idStr -> case readMaybe (T.unpack idStr) of
        Just eid -> pure (Right eid)
        Nothing  -> pure (Left (GrocyCreateError entityType ("bad id: " <> T.unpack idStr)))
      Nothing -> pure (Left (GrocyCreateError entityType "no created_object_id"))

discreteToScientific :: Discrete "USD" "cent" -> Scientific
discreteToScientific d = scientific (toInteger d) (-2)

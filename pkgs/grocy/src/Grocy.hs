{-# LANGUAGE OverloadedStrings #-}

-- | Grocy REST API client.
--
-- Covers the object and stock endpoints of the Grocy v4 API:
-- products, locations, shopping locations, quantity units, and
-- stock purchases.
module Grocy
  ( -- * Environment
    Env
  , newEnv
  , BaseUrl (..)
  , ApiKey (..)
    -- * Types
  , ProductId (..)
  , LocationId (..)
  , ShoppingLocationId (..)
  , QuantityUnitId (..)
  , Product (..)
  , NewProduct (..)
  , StockPurchase (..)
  , neverExpires
  , ObjectCollection (..)
  , ObjectRef (..)
  , ApiPath (..)
  , GrocyError (..)
    -- * Operations
  , getProducts
  , createProduct
  , addStock
  , ensureLocation
  , ensureShoppingLocation
  , findQuantityUnit
  , deleteObject
  ) where

import Control.Exception (displayException, try)
import Data.Aeson ((.:), (.=))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Scientific (Scientific, scientific)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (Day, fromGregorian)
import Data.Time.Format.ISO8601 (iso8601Show)
import Money (Discrete)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Method (Method)
import Network.HTTP.Types.Status (statusCode)
import Text.Read (readMaybe)

newtype BaseUrl = BaseUrl { unBaseUrl :: Text }
  deriving stock (Show, Eq)

newtype ApiKey = ApiKey { unApiKey :: Text }

data Env = Env
  { envManager :: Manager
  , envBaseUrl :: BaseUrl
  , envApiKey  :: ApiKey
  }

newEnv :: BaseUrl -> ApiKey -> IO Env
newEnv baseUrl apiKey = do
  mgr <- newManager tlsManagerSettings
  pure Env { envManager = mgr, envBaseUrl = baseUrl, envApiKey = apiKey }

newtype ProductId = ProductId { unProductId :: Int }
  deriving stock (Show, Eq, Ord)

instance Aeson.ToJSON ProductId where
  toJSON = Aeson.toJSON . unProductId

newtype LocationId = LocationId { unLocationId :: Int }
  deriving stock (Show, Eq)

newtype ShoppingLocationId = ShoppingLocationId { unShoppingLocationId :: Int }
  deriving stock (Show, Eq)

newtype QuantityUnitId = QuantityUnitId { unQuantityUnitId :: Int }
  deriving stock (Show, Eq)

data Product = Product
  { productId   :: ProductId
  , productName :: Text
  } deriving stock (Show, Eq)

instance Aeson.FromJSON Product where
  parseJSON = Aeson.withObject "Product" $ \obj ->
    Product <$> (ProductId <$> obj .: "id") <*> obj .: "name"

instance Aeson.ToJSON Product where
  toJSON p = Aeson.object ["id" .= productId p, "name" .= productName p]

data NewProduct = NewProduct
  { newProductName             :: Text
  , newProductLocation         :: LocationId
  , newProductQuantityUnit     :: QuantityUnitId
  , newProductShoppingLocation :: ShoppingLocationId
  } deriving stock (Show)

data StockPurchase = StockPurchase
  { purchaseAmount     :: Scientific
  , purchasePrice      :: Maybe (Discrete "USD" "cent")
  , purchasedOn        :: Day
  , purchaseBestBefore :: Day
  } deriving stock (Show)

-- | Grocy's UI renders this best-before date as \"never expires\".
neverExpires :: Day
neverExpires = fromGregorian 2999 12 31

-- | The object collections this client addresses.
data ObjectCollection = Products | Locations | ShoppingLocations | QuantityUnits
  deriving stock (Show, Eq)

-- | One object, identified by the id type that indexes its collection.
-- Pairing the two means a location id cannot be passed where a product
-- id belongs.
data ObjectRef
  = ProductRef ProductId
  | LocationRef LocationId
  | ShoppingLocationRef ShoppingLocationId
  | QuantityUnitRef QuantityUnitId
  deriving stock (Show, Eq)

refCollection :: ObjectRef -> ObjectCollection
refCollection (ProductRef _)          = Products
refCollection (LocationRef _)         = Locations
refCollection (ShoppingLocationRef _) = ShoppingLocations
refCollection (QuantityUnitRef _)     = QuantityUnits

refObjectId :: ObjectRef -> Int
refObjectId (ProductRef pid)          = unProductId pid
refObjectId (LocationRef lid)         = unLocationId lid
refObjectId (ShoppingLocationRef sid) = unShoppingLocationId sid
refObjectId (QuantityUnitRef qid)     = unQuantityUnitId qid

newtype ApiPath = ApiPath { unApiPath :: Text }
  deriving stock (Show, Eq)

data GrocyError
  = GrocyNetworkError ApiPath Text
  | GrocyHttpError ApiPath Int Text
  | GrocyParseError ApiPath Text
  | GrocyObjectNotFound ObjectCollection Text
  deriving stock (Show, Eq)

-- * Operations

getProducts :: Env -> IO (Either GrocyError [Product])
getProducts env = getJson env (collectionPath Products)

createProduct :: Env -> NewProduct -> IO (Either GrocyError Product)
createProduct env new = do
  let payload = Aeson.object
        [ "name"                 .= newProductName new
        , "location_id"          .= unLocationId (newProductLocation new)
        , "qu_id_purchase"       .= unQuantityUnitId (newProductQuantityUnit new)
        , "qu_id_stock"          .= unQuantityUnitId (newProductQuantityUnit new)
        , "shopping_location_id" .= unShoppingLocationId (newProductShoppingLocation new)
        ]
  created <- postForId env (collectionPath Products) payload
  pure $ fmap (\pid -> Product { productId = ProductId pid, productName = newProductName new }) created

addStock :: Env -> ProductId -> StockPurchase -> IO (Either GrocyError ())
addStock env pid purchase = do
  let path = "/api/stock/products/" <> T.pack (show (unProductId pid)) <> "/add"
      payload = Aeson.object $
        [ "amount"           .= purchaseAmount purchase
        , "transaction_type" .= ("purchase" :: Text)
        , "best_before_date" .= iso8601Show (purchaseBestBefore purchase)
        , "purchased_date"   .= iso8601Show (purchasedOn purchase)
        ]
        <> maybe [] (\price -> ["price" .= centsToDollars price]) (purchasePrice purchase)
  attempt <- request env "POST" path (Just payload)
  pure $ attempt >>= \resp ->
    let code = statusCode (responseStatus resp)
    in if code == 200
         then Right ()
         else Left (GrocyHttpError (ApiPath path) code (bodyPreview resp))

-- | Permanently remove one object. Grocy answers 400 when it refuses,
-- which surfaces as a 'GrocyHttpError' carrying its explanation.
deleteObject :: Env -> ObjectRef -> IO (Either GrocyError ())
deleteObject env ref = do
  let path = collectionPath (refCollection ref) <> "/" <> T.pack (show (refObjectId ref))
  attempt <- request env "DELETE" path Nothing
  pure $ attempt >>= \resp ->
    let code = statusCode (responseStatus resp)
    -- The API documents 204 for a successful delete.
    in if code == 204
         then Right ()
         else Left (GrocyHttpError (ApiPath path) code (bodyPreview resp))

ensureLocation :: Env -> Text -> IO (Either GrocyError LocationId)
ensureLocation env name = fmap LocationId <$> ensureObject env Locations name

ensureShoppingLocation :: Env -> Text -> IO (Either GrocyError ShoppingLocationId)
ensureShoppingLocation env name = fmap ShoppingLocationId <$> ensureObject env ShoppingLocations name

findQuantityUnit :: Env -> Text -> IO (Either GrocyError QuantityUnitId)
findQuantityUnit env name = do
  found <- findObject env QuantityUnits name
  pure $ case found of
    Left err          -> Left err
    Right Nothing     -> Left (GrocyObjectNotFound QuantityUnits name)
    Right (Just oid)  -> Right (QuantityUnitId oid)

-- * Named objects

data NamedObject = NamedObject
  { objectId   :: Int
  , objectName :: Text
  }

instance Aeson.FromJSON NamedObject where
  parseJSON = Aeson.withObject "NamedObject" $ \obj ->
    NamedObject <$> obj .: "id" <*> obj .: "name"

collectionPath :: ObjectCollection -> Text
collectionPath Products          = "/api/objects/products"
collectionPath Locations         = "/api/objects/locations"
collectionPath ShoppingLocations = "/api/objects/shopping_locations"
collectionPath QuantityUnits     = "/api/objects/quantity_units"

ensureObject :: Env -> ObjectCollection -> Text -> IO (Either GrocyError Int)
ensureObject env collection name = do
  found <- findObject env collection name
  case found of
    Left err          -> pure (Left err)
    Right (Just oid)  -> pure (Right oid)
    Right Nothing     -> postForId env (collectionPath collection) (Aeson.object ["name" .= name])

findObject :: Env -> ObjectCollection -> Text -> IO (Either GrocyError (Maybe Int))
findObject env collection name = do
  objects <- getJson env (collectionPath collection)
  pure $ fmap (lookupByName name) objects

lookupByName :: Text -> [NamedObject] -> Maybe Int
lookupByName name objects =
  case filter (\obj -> objectName obj == name) objects of
    (obj : _) -> Just (objectId obj)
    []        -> Nothing

-- * HTTP plumbing

request :: Env -> Method -> Text -> Maybe Aeson.Value -> IO (Either GrocyError (Response LBS.ByteString))
request env method path mBody = do
  attempt <- try $ do
    req0 <- parseRequest (T.unpack (unBaseUrl (envBaseUrl env) <> path))
    let req = req0
          { method = method
          , requestHeaders =
              [ ("GROCY-API-KEY", TE.encodeUtf8 (unApiKey (envApiKey env)))
              , ("accept", "application/json")
              , ("content-type", "application/json")
              ]
          , requestBody = maybe (requestBody req0) (RequestBodyLBS . Aeson.encode) mBody
          }
    httpLbs req (envManager env)
  pure $ case attempt of
    Left err   -> Left (GrocyNetworkError (ApiPath path) (T.pack (displayException (err :: HttpException))))
    Right resp -> Right resp

-- | The first 200 characters of a response body, kept for diagnostics.
bodyPreview :: Response LBS.ByteString -> Text
bodyPreview = T.take 200 . TE.decodeUtf8Lenient . LBS.toStrict . responseBody

getJson :: Aeson.FromJSON a => Env -> Text -> IO (Either GrocyError a)
getJson env path = do
  attempt <- request env "GET" path Nothing
  pure $ attempt >>= \resp ->
    let code = statusCode (responseStatus resp)
    in if code == 200
         then case Aeson.eitherDecode (responseBody resp) of
           Left err  -> Left (GrocyParseError (ApiPath path) (T.pack err))
           Right val -> Right val
         else Left (GrocyHttpError (ApiPath path) code (bodyPreview resp))

-- | Grocy reports a created object's id as a decimal string.
newtype CreatedObjectId = CreatedObjectId Text

instance Aeson.FromJSON CreatedObjectId where
  parseJSON = Aeson.withObject "created" $ \obj ->
    CreatedObjectId <$> obj .: "created_object_id"

postForId :: Env -> Text -> Aeson.Value -> IO (Either GrocyError Int)
postForId env path payload = do
  attempt <- request env "POST" path (Just payload)
  pure $ attempt >>= \resp ->
    let code = statusCode (responseStatus resp)
    in if code == 200
         then case Aeson.eitherDecode (responseBody resp) of
           Left err -> Left (GrocyParseError (ApiPath path) (T.pack err))
           Right (CreatedObjectId idText) -> case readMaybe (T.unpack idText) of
             Just oid -> Right oid
             Nothing  -> Left (GrocyParseError (ApiPath path) ("created_object_id is not a number: " <> idText))
         else Left (GrocyHttpError (ApiPath path) code (bodyPreview resp))

centsToDollars :: Discrete "USD" "cent" -> Scientific
centsToDollars cents = scientific (toInteger cents) (-2)

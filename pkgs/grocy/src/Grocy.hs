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
  , ensureQuantityUnit
  , deleteObject
    -- * Stock
  , StockLine (..)
  , getStock
  , ProductDetails (..)
  , getProductDetails
  , consumeProduct
  , searchProducts
    -- * Barcodes
  , Barcode (..)
  , addProductBarcode
  , findProductByBarcode
    -- * Units
  , UnitConversion (..)
  , addUnitConversion
    -- * Recipes
  , RecipeId (..)
  , NewRecipe (..)
  , Recipe (..)
  , Ingredient (..)
  , RecipeFulfillment (..)
  , createRecipe
  , RecipeChanges (..)
  , updateRecipe
  , getRecipes
  , addIngredient
  , IngredientId (..)
  , setIngredientAmount
  , getIngredients
  , recipeFulfillment
  , consumeRecipe
    -- * Userfields
  , UserfieldEntity (..)
  , ensureUserfield
  , setUserfields
  , getUserfields
    -- * Parsers
  , parseStockLines
  , parseProductDetails
  , parseRecipeFulfillment
  , parseIngredients
  , parseRecipes
  ) where

import Control.Exception (displayException, try)
import Data.Aeson ((.:), (.:?), (.!=), (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (Parser, parseEither)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Scientific (Scientific, fromFloatDigits, toRealFloat)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (Day, fromGregorian)
import Data.Time.Format.ISO8601 (iso8601ParseM, iso8601Show)
import Money (Discrete, discrete)
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
  { purchaseAmount           :: Scientific
    -- | What the whole line cost, not the unit price.
  , purchasePrice            :: Maybe (Discrete "USD" "cent")
  , purchasedOn              :: Day
  , purchaseBestBefore       :: Day
  , purchaseShoppingLocation :: Maybe ShoppingLocationId
  , purchaseNote             :: Maybe Text
  } deriving stock (Show)

-- | Grocy's UI renders this best-before date as \"never expires\".
neverExpires :: Day
neverExpires = fromGregorian 2999 12 31

-- | The object collections this client addresses.
data ObjectCollection
  = Products | Locations | ShoppingLocations | QuantityUnits
  | Recipes | RecipePositions | ProductBarcodes | UnitConversions | Userfields
  deriving stock (Show, Eq)

-- | One object, identified by the id type that indexes its collection.
-- Pairing the two means a location id cannot be passed where a product
-- id belongs.
data ObjectRef
  = ProductRef ProductId
  | LocationRef LocationId
  | ShoppingLocationRef ShoppingLocationId
  | QuantityUnitRef QuantityUnitId
  | RecipeRef RecipeId
  deriving stock (Show, Eq)

refCollection :: ObjectRef -> ObjectCollection
refCollection (ProductRef _)          = Products
refCollection (LocationRef _)         = Locations
refCollection (ShoppingLocationRef _) = ShoppingLocations
refCollection (QuantityUnitRef _)     = QuantityUnits
refCollection (RecipeRef _)           = Recipes

refObjectId :: ObjectRef -> Int
refObjectId (ProductRef pid)          = unProductId pid
refObjectId (LocationRef lid)         = unLocationId lid
refObjectId (ShoppingLocationRef sid) = unShoppingLocationId sid
refObjectId (QuantityUnitRef qid)     = unQuantityUnitId qid
refObjectId (RecipeRef rid)           = unRecipeId rid

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
        -- Grocy prices a stock entry per stock unit; the purchase carries
        -- what the whole line cost.
        <> maybe [] (\price -> ["price" .= unitPrice price (purchaseAmount purchase)]) (purchasePrice purchase)
        <> maybe [] (\sid -> ["shopping_location_id" .= unShoppingLocationId sid]) (purchaseShoppingLocation purchase)
        <> maybe [] (\n -> ["note" .= n]) (purchaseNote purchase)
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

-- | The id of the named quantity unit, creating it when Grocy lacks it.
-- Grocy wants a plural form too; the name serves for both.
ensureQuantityUnit :: Env -> Text -> IO (Either GrocyError QuantityUnitId)
ensureQuantityUnit env name = do
  found <- findObject env QuantityUnits name
  case found of
    Left err -> pure (Left err)
    Right (Just qid) -> pure (Right (QuantityUnitId qid))
    Right Nothing -> fmap QuantityUnitId <$> postForId env (collectionPath QuantityUnits)
      (Aeson.object [ "name" .= name, "name_plural" .= name ])

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
collectionPath Recipes           = "/api/objects/recipes"
collectionPath RecipePositions   = "/api/objects/recipes_pos"
collectionPath ProductBarcodes   = "/api/objects/product_barcodes"
collectionPath UnitConversions   = "/api/objects/quantity_unit_conversions"
collectionPath Userfields        = "/api/objects/userfields"

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

-- | Dollars per stock unit for a line that cost this much in total.
-- Scientific division throws on a non-terminating quotient, so the
-- quotient is taken in Double and kept to four decimals.
unitPrice :: Discrete "USD" "cent" -> Scientific -> Scientific
unitPrice total amount =
  let cents = fromInteger (toInteger total) :: Double
      perUnit = cents / toRealFloat amount / 100
  in fromFloatDigits (fromIntegral (round (perUnit * 10000) :: Integer) / 10000 :: Double)


-- * Stock

-- | One product's presence in stock: how much there is, how much of
-- that is opened, and when the next of it is due.
data StockLine = StockLine
  { slProduct      :: Product
  , slAmount       :: Scientific
  , slAmountOpened :: Scientific
  , slNextDue      :: Maybe Day
  } deriving stock (Show, Eq)

instance Aeson.ToJSON StockLine where
  toJSON l = Aeson.object
    [ "product"       .= slProduct l
    , "amount"        .= slAmount l
    , "amount_opened" .= slAmountOpened l
    , "next_due"      .= slNextDue l
    ]

getStock :: Env -> IO (Either GrocyError [StockLine])
getStock env = do
  body <- getJson env "/api/stock"
  pure (body >>= first' "/api/stock" parseStockLines)

parseStockLines :: Aeson.Value -> Either String [StockLine]
parseStockLines = parseEither (Aeson.withArray "stock" (traverse parseLine . foldr (:) []))
  where
    parseLine = Aeson.withObject "stockLine" $ \obj -> do
      prod <- obj .: "product"
      StockLine prod
        <$> obj .: "amount"
        <*> obj .:? "amount_opened" .!= 0
        <*> (traverse parseDay =<< obj .:? "best_before_date")

-- | Everything Grocy knows about one product's stock position.
data ProductDetails = ProductDetails
  { pdProduct       :: Product
  , pdStockAmount   :: Scientific
  , pdStockOpened   :: Scientific
  , pdLastPrice     :: Maybe (Discrete "USD" "cent")
  , pdLastPurchased :: Maybe Day
  , pdNextDue       :: Maybe Day
  , pdStockUnit     :: Text
  , pdPurchaseUnit  :: Text
  , pdLocation      :: Maybe Text
  , pdBarcodes      :: [Barcode]
  } deriving stock (Show, Eq)

instance Aeson.ToJSON ProductDetails where
  toJSON d = Aeson.object
    [ "product"          .= pdProduct d
    , "stock_amount"     .= pdStockAmount d
    , "stock_opened"     .= pdStockOpened d
    , "last_price_cents" .= fmap toInteger (pdLastPrice d)
    , "last_purchased"   .= pdLastPurchased d
    , "next_due"         .= pdNextDue d
    , "stock_unit"       .= pdStockUnit d
    , "purchase_unit"    .= pdPurchaseUnit d
    , "location"         .= pdLocation d
    , "barcodes"         .= pdBarcodes d
    ]

getProductDetails :: Env -> ProductId -> IO (Either GrocyError ProductDetails)
getProductDetails env pid = do
  let path = "/api/stock/products/" <> T.pack (show (unProductId pid))
  body <- getJson env path
  pure (body >>= first' path parseProductDetails)

parseProductDetails :: Aeson.Value -> Either String ProductDetails
parseProductDetails = parseEither $ Aeson.withObject "productDetails" $ \obj -> do
  prod <- obj .: "product"
  stockUnit <- (.: "name") =<< obj .: "quantity_unit_stock"
  purchaseUnit <- (.: "name") =<< obj .: "default_quantity_unit_purchase"
  mLocation <- obj .:? "location"
  location <- traverse (.: "name") mLocation
  barcodeRows <- obj .:? "product_barcodes" .!= ([] :: [Aeson.Object])
  barcodes <- traverse (fmap Barcode . (.: "barcode")) barcodeRows
  ProductDetails prod
    <$> obj .: "stock_amount"
    <*> obj .:? "stock_amount_opened" .!= 0
    <*> (fmap dollarsToCents <$> obj .:? "last_price")
    <*> (traverse parseDay =<< obj .:? "last_purchased")
    <*> (traverse parseDay =<< obj .:? "next_due_date")
    <*> pure stockUnit
    <*> pure purchaseUnit
    <*> pure location
    <*> pure barcodes

-- | Take an amount out of stock, as used (not spoiled).
consumeProduct :: Env -> ProductId -> Scientific -> IO (Either GrocyError ())
consumeProduct env pid amount = do
  let path = "/api/stock/products/" <> T.pack (show (unProductId pid)) <> "/consume"
      payload = Aeson.object
        [ "amount"           .= amount
        , "transaction_type" .= ("consume" :: Text)
        , "spoiled"          .= False
        ]
  expectStatus 200 path =<< request env "POST" path (Just payload)

-- | Products whose name contains the term, matched by Grocy.
searchProducts :: Env -> Text -> IO (Either GrocyError [Product])
searchProducts env term =
  getJson env (collectionPath Products <> "?query%5B%5D=name~" <> term)

-- * Barcodes

-- | A barcode as Grocy stores it: any text, since Grocy also accepts
-- its own printed codes. Callers link the package UPC here.
newtype Barcode = Barcode { unBarcode :: Text }
  deriving stock (Show, Eq)

instance Aeson.ToJSON Barcode where
  toJSON = Aeson.toJSON . unBarcode

addProductBarcode :: Env -> ProductId -> Barcode -> Maybe Text -> IO (Either GrocyError ())
addProductBarcode env pid barcode note = do
  let payload = Aeson.object $
        [ "product_id" .= unProductId pid
        , "barcode"    .= unBarcode barcode
        ] <> maybe [] (\n -> ["note" .= n]) note
  fmap (const ()) <$> postForId env (collectionPath ProductBarcodes) payload

-- | The product a barcode is linked to, or nothing when no product
-- carries it. Grocy reports the latter as HTTP 400 with a message.
findProductByBarcode :: Env -> Barcode -> IO (Either GrocyError (Maybe ProductDetails))
findProductByBarcode env barcode = do
  let path = "/api/stock/products/by-barcode/" <> unBarcode barcode
  attempt <- request env "GET" path Nothing
  pure $ attempt >>= \resp ->
    let code = statusCode (responseStatus resp)
        body = responseBody resp
    in case code of
      200 -> case Aeson.eitherDecode body >>= parseProductDetails of
        Left err -> Left (GrocyParseError (ApiPath path) (T.pack err))
        Right details -> Right (Just details)
      400 | "No product with barcode" `T.isInfixOf` bodyPreview resp -> Right Nothing
      _ -> Left (GrocyHttpError (ApiPath path) code (bodyPreview resp))

-- * Units

-- | How many of one unit make one of another, for one product (a pound
-- of beef is 16 ounces) or for every product when no product is named.
data UnitConversion = UnitConversion
  { ucFrom    :: QuantityUnitId
  , ucTo      :: QuantityUnitId
  , ucFactor  :: Scientific
  , ucProduct :: Maybe ProductId
  } deriving stock (Show, Eq)

addUnitConversion :: Env -> UnitConversion -> IO (Either GrocyError ())
addUnitConversion env conv = do
  let payload = Aeson.object $
        [ "from_qu_id" .= unQuantityUnitId (ucFrom conv)
        , "to_qu_id"   .= unQuantityUnitId (ucTo conv)
        , "factor"     .= ucFactor conv
        ] <> maybe [] (\p -> ["product_id" .= unProductId p]) (ucProduct conv)
  fmap (const ()) <$> postForId env (collectionPath UnitConversions) payload

-- * Recipes

newtype RecipeId = RecipeId { unRecipeId :: Int }
  deriving stock (Show, Eq)

instance Aeson.ToJSON RecipeId where
  toJSON = Aeson.toJSON . unRecipeId

data NewRecipe = NewRecipe
  { newRecipeName         :: Text
  , newRecipeDescription  :: Maybe Text
  , newRecipeBaseServings :: Int
  } deriving stock (Show)

data Recipe = Recipe
  { recipeId           :: RecipeId
  , recipeName         :: Text
  , recipeBaseServings :: Scientific
  } deriving stock (Show, Eq)

instance Aeson.ToJSON Recipe where
  toJSON r = Aeson.object
    [ "id"            .= recipeId r
    , "name"          .= recipeName r
    , "base_servings" .= recipeBaseServings r
    ]

createRecipe :: Env -> NewRecipe -> IO (Either GrocyError Recipe)
createRecipe env new = do
  let payload = Aeson.object $
        [ "name"          .= newRecipeName new
        , "base_servings" .= newRecipeBaseServings new
        ] <> maybe [] (\d -> ["description" .= d]) (newRecipeDescription new)
  created <- postForId env (collectionPath Recipes) payload
  pure $ fmap (\rid -> Recipe
    { recipeId           = RecipeId rid
    , recipeName         = newRecipeName new
    , recipeBaseServings = fromIntegral (newRecipeBaseServings new)
    }) created

-- | What an existing recipe may be changed to. A field left 'Nothing'
-- keeps its current value.
data RecipeChanges = RecipeChanges
  { changeName         :: Maybe Text
  , changeDescription  :: Maybe Text
  , changeBaseServings :: Maybe Int
  } deriving stock (Show)

updateRecipe :: Env -> RecipeId -> RecipeChanges -> IO (Either GrocyError ())
updateRecipe env rid changes = do
  let path = collectionPath Recipes <> "/" <> T.pack (show (unRecipeId rid))
      payload = Aeson.object $ concat
        [ maybe [] (\n -> ["name" .= n]) (changeName changes)
        , maybe [] (\d -> ["description" .= d]) (changeDescription changes)
        , maybe [] (\s -> ["base_servings" .= s]) (changeBaseServings changes)
        ]
  expectStatus 204 path =<< request env "PUT" path (Just payload)

-- | The recipes a person wrote. Grocy keeps its meal-plan bookkeeping
-- in the same table under negative ids and a type other than
-- @normal@, which is left out.
getRecipes :: Env -> IO (Either GrocyError [Recipe])
getRecipes env = do
  body <- getJson env (collectionPath Recipes)
  pure (body >>= first' (collectionPath Recipes) parseRecipes)

parseRecipes :: Aeson.Value -> Either String [Recipe]
parseRecipes = parseEither (Aeson.withArray "recipes" (fmap concat . traverse parseRow . foldr (:) []))
  where
    parseRow = Aeson.withObject "recipe" $ \obj -> do
      kind <- obj .:? "type" .!= ("normal" :: Text)
      if kind /= "normal" then pure [] else do
        r <- Recipe <$> (RecipeId <$> obj .: "id") <*> obj .: "name" <*> obj .:? "base_servings" .!= 1
        pure [r]

-- | One line of a recipe: a product in some amount of some unit.
data Ingredient = Ingredient
  { ingredientId      :: Maybe IngredientId
  , ingredientProduct :: ProductId
  , ingredientAmount  :: Scientific
  , ingredientUnit    :: QuantityUnitId
  , ingredientNote    :: Maybe Text
  } deriving stock (Show, Eq)

instance Aeson.ToJSON Ingredient where
  toJSON i = Aeson.object
    [ "ingredient_id" .= ingredientId i
    , "product_id" .= ingredientProduct i
    , "amount"     .= ingredientAmount i
    , "unit_id"    .= unQuantityUnitId (ingredientUnit i)
    , "note"       .= ingredientNote i
    ]

addIngredient :: Env -> RecipeId -> Ingredient -> IO (Either GrocyError ())
addIngredient env rid ingredient = do
  let payload = Aeson.object $
        [ "recipe_id"  .= unRecipeId rid
        , "product_id" .= unProductId (ingredientProduct ingredient)
        , "amount"     .= ingredientAmount ingredient
        , "qu_id"      .= unQuantityUnitId (ingredientUnit ingredient)
        ] <> maybe [] (\n -> ["note" .= n]) (ingredientNote ingredient)
  fmap (const ()) <$> postForId env (collectionPath RecipePositions) payload

newtype IngredientId = IngredientId { unIngredientId :: Int }
  deriving stock (Show, Eq)

instance Aeson.ToJSON IngredientId where
  toJSON = Aeson.toJSON . unIngredientId

-- | Change how much of its product one ingredient line calls for.
setIngredientAmount :: Env -> IngredientId -> Scientific -> IO (Either GrocyError ())
setIngredientAmount env iid amount = do
  let path = collectionPath RecipePositions <> "/" <> T.pack (show (unIngredientId iid))
  expectStatus 204 path =<< request env "PUT" path (Just (Aeson.object [ "amount" .= amount ]))

getIngredients :: Env -> RecipeId -> IO (Either GrocyError [Ingredient])
getIngredients env rid = do
  let path = collectionPath RecipePositions <> "?query%5B%5D=recipe_id%3D" <> T.pack (show (unRecipeId rid))
  body <- getJson env path
  pure (body >>= first' path parseIngredients)

parseIngredients :: Aeson.Value -> Either String [Ingredient]
parseIngredients = parseEither (Aeson.withArray "recipes_pos" (traverse parseRow . foldr (:) []))
  where
    parseRow = Aeson.withObject "recipe_pos" $ \obj ->
      Ingredient
        <$> (fmap IngredientId <$> obj .:? "id")
        <*> (ProductId <$> obj .: "product_id")
        <*> obj .: "amount"
        <*> (QuantityUnitId <$> obj .: "qu_id")
        <*> obj .:? "note"

-- | Whether stock covers a recipe, and what it would cost.
data RecipeFulfillment = RecipeFulfillment
  { fulfilled            :: Bool
  , missingProductsCount :: Int
  , recipeCost           :: Maybe Scientific
  } deriving stock (Show, Eq)

instance Aeson.ToJSON RecipeFulfillment where
  toJSON f = Aeson.object
    [ "fulfilled"              .= fulfilled f
    , "missing_products_count" .= missingProductsCount f
    , "cost"                   .= recipeCost f
    ]

recipeFulfillment :: Env -> RecipeId -> IO (Either GrocyError RecipeFulfillment)
recipeFulfillment env rid = do
  let path = "/api/recipes/" <> T.pack (show (unRecipeId rid)) <> "/fulfillment"
  body <- getJson env path
  pure (body >>= first' path parseRecipeFulfillment)

parseRecipeFulfillment :: Aeson.Value -> Either String RecipeFulfillment
parseRecipeFulfillment = parseEither $ Aeson.withObject "fulfillment" $ \obj ->
  RecipeFulfillment
    <$> (flag =<< obj .: "need_fulfilled")
    <*> obj .: "missing_products_count"
    <*> obj .:? "costs"
  where
    -- Grocy documents the field as boolean and serves it as 0 or 1.
    flag :: Aeson.Value -> Parser Bool
    flag (Aeson.Bool b) = pure b
    flag (Aeson.Number n) = pure (n /= 0)
    flag other = fail ("need_fulfilled is neither boolean nor number: " <> show other)

-- | Take every ingredient of a recipe out of stock in one booking.
consumeRecipe :: Env -> RecipeId -> IO (Either GrocyError ())
consumeRecipe env rid = do
  let path = "/api/recipes/" <> T.pack (show (unRecipeId rid)) <> "/consume"
  expectStatus 204 path =<< request env "POST" path Nothing

-- * Userfields

-- | The entities this client attaches custom fields to.
data UserfieldEntity = ProductFields | RecipeFields
  deriving stock (Show, Eq)

entityName :: UserfieldEntity -> Text
entityName ProductFields = "products"
entityName RecipeFields  = "recipes"

-- | Declare a single-line text field on an entity, once. Grocy refuses
-- to store a value for a field it has no definition of.
ensureUserfield :: Env -> UserfieldEntity -> Text -> IO (Either GrocyError ())
ensureUserfield env entity name = do
  defined <- getJson env (collectionPath Userfields) :: IO (Either GrocyError [Aeson.Object])
  case defined of
    Left err -> pure (Left err)
    Right rows
      | any matches rows -> pure (Right ())
      | otherwise -> fmap (const ()) <$> postForId env (collectionPath Userfields) (Aeson.object
          [ "entity"  .= entityName entity
          , "name"    .= name
          , "caption" .= name
          , "type"    .= ("text-single-line" :: Text)
          ])
  where
    matches row =
      KM.lookup "entity" row == Just (Aeson.String (entityName entity))
        && KM.lookup "name" row == Just (Aeson.String name)

setUserfields :: Env -> UserfieldEntity -> Int -> [(Text, Text)] -> IO (Either GrocyError ())
setUserfields env entity oid fields = do
  let path = "/api/userfields/" <> entityName entity <> "/" <> T.pack (show oid)
      payload = Aeson.object [ Key.fromText k .= v | (k, v) <- fields ]
  expectStatus 204 path =<< request env "PUT" path (Just payload)

getUserfields :: Env -> UserfieldEntity -> Int -> IO (Either GrocyError [(Text, Text)])
getUserfields env entity oid = do
  let path = "/api/userfields/" <> entityName entity <> "/" <> T.pack (show oid)
  body <- getJson env path
  pure $ body >>= \value -> case value of
    Aeson.Object obj -> Right [ (Key.toText k, t) | (k, Aeson.String t) <- KM.toList obj ]
    Aeson.Array _    -> Right []
    other -> Left (GrocyParseError (ApiPath path) ("userfields are not an object: " <> T.pack (show other)))

-- * Shared plumbing for the additions

first' :: Text -> (Aeson.Value -> Either String a) -> Aeson.Value -> Either GrocyError a
first' path parser value = case parser value of
  Left err -> Left (GrocyParseError (ApiPath path) (T.pack err))
  Right x  -> Right x

expectStatus :: Int -> Text -> Either GrocyError (Response LBS.ByteString) -> IO (Either GrocyError ())
expectStatus wanted path attempt = pure $ attempt >>= \resp ->
  let code = statusCode (responseStatus resp)
  in if code == wanted
       then Right ()
       else Left (GrocyHttpError (ApiPath path) code (bodyPreview resp))

parseDay :: Text -> Parser Day
parseDay raw = case iso8601ParseM (T.unpack raw) of
  Just day -> pure day
  Nothing  -> fail ("not a YYYY-MM-DD date: " <> show raw)

dollarsToCents :: Scientific -> Discrete "USD" "cent"
dollarsToCents s = discrete (round (s * 100))

-- | Open Food Facts: the open product database keyed by barcode.
--
-- A product page's UPC is the key; what comes back is the label as
-- volunteers and manufacturers transcribed it. Coverage is uneven, so
-- every nutrient is optional and a barcode the database has never seen
-- is an ordinary answer, not an error.
module OpenFoodFacts
  ( Env
  , newEnv
  , UserAgent (..)
  , Barcode (..)
  , Product (..)
  , Nutrients (..)
  , OffError (..)
  , lookupProduct
  , parseProductResponse
  ) where

import Control.Exception (displayException, try)
import Data.Aeson (Value, eitherDecode, withObject, (.:), (.:?), (.!=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.Types (Object, Parser, parseEither)
import Data.ByteString.Lazy qualified as LBS
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.HTTP.Client
  ( HttpException
  , Manager
  , httpLbs
  , newManager
  , parseRequest
  , requestHeaders
  , responseBody
  , responseStatus
  )
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Status (statusCode)

-- | Open Food Facts asks every client to identify itself.
newtype UserAgent = UserAgent { unUserAgent :: Text }
  deriving stock (Show, Eq)

data Env = Env
  { envManager   :: Manager
  , envUserAgent :: UserAgent
  }

newEnv :: UserAgent -> IO Env
newEnv agent = do
  mgr <- newManager tlsManagerSettings
  pure Env { envManager = mgr, envUserAgent = agent }

-- | A product barcode as printed: UPC-A (12 digits) or EAN-13.
newtype Barcode = Barcode { unBarcode :: Text }
  deriving stock (Show, Eq)

instance Aeson.ToJSON Barcode where
  toJSON = Aeson.toJSON . unBarcode

-- | Amounts in grams, energy in kilocalories, for one reference
-- quantity (100 g or one serving). Absent means the label entry was
-- never transcribed.
data Nutrients = Nutrients
  { nCalories     :: Maybe Scientific
  , nProtein      :: Maybe Scientific
  , nFat          :: Maybe Scientific
  , nSaturatedFat :: Maybe Scientific
  , nCarbohydrate :: Maybe Scientific
  , nSugars       :: Maybe Scientific
  , nFiber        :: Maybe Scientific
  , nSodium       :: Maybe Scientific
  } deriving stock (Show, Eq)

instance Aeson.ToJSON Nutrients where
  toJSON n = Aeson.object
    [ "calories_kcal"     Aeson..= nCalories n
    , "protein_g"         Aeson..= nProtein n
    , "fat_g"             Aeson..= nFat n
    , "saturated_fat_g"   Aeson..= nSaturatedFat n
    , "carbohydrate_g"    Aeson..= nCarbohydrate n
    , "sugars_g"          Aeson..= nSugars n
    , "fiber_g"           Aeson..= nFiber n
    , "sodium_g"          Aeson..= nSodium n
    ]

data Product = Product
  { offBarcode     :: Barcode
  , offName        :: Maybe Text
  , offBrands      :: Maybe Text
    -- | Package size as transcribed, e.g. "1 gallon".
  , offQuantity    :: Maybe Text
  , offServingSize :: Maybe Text
  , offIngredients :: Maybe Text
  , offPer100g     :: Nutrients
  , offPerServing  :: Nutrients
  } deriving stock (Show, Eq)

instance Aeson.ToJSON Product where
  toJSON p = Aeson.object
    [ "barcode"      Aeson..= offBarcode p
    , "name"         Aeson..= offName p
    , "brands"       Aeson..= offBrands p
    , "quantity"     Aeson..= offQuantity p
    , "serving_size" Aeson..= offServingSize p
    , "ingredients"  Aeson..= offIngredients p
    , "per_100g"     Aeson..= offPer100g p
    , "per_serving"  Aeson..= offPerServing p
    , "source"       Aeson..= ("Open Food Facts" :: Text)
    ]

data OffError
  = OffNetworkError Text
  | OffHttpError Int Text
  | OffParseError String
  deriving stock (Show, Eq)

baseUrl :: Text
baseUrl = "https://world.openfoodfacts.org/api/v2/product/"

fields :: Text
fields = "code,product_name,brands,quantity,serving_size,ingredients_text,nutriments"

-- | Look a barcode up. 'Nothing' is the database saying it has no such
-- product, which it reports as HTTP 404 with a status body.
lookupProduct :: Env -> Barcode -> IO (Either OffError (Maybe Product))
lookupProduct env barcode = do
  attempt <- try $ do
    req0 <- parseRequest (T.unpack (baseUrl <> unBarcode barcode <> ".json?fields=" <> fields))
    let req = req0 { requestHeaders = [("User-Agent", TE.encodeUtf8 (unUserAgent (envUserAgent env)))] }
    httpLbs req (envManager env)
  pure $ case attempt of
    Left err -> Left (OffNetworkError (T.pack (displayException (err :: HttpException))))
    Right resp ->
      let code = statusCode (responseStatus resp)
          body = responseBody resp
      in if code == 200 || code == 404
        then either (Left . OffParseError) Right (eitherDecode body >>= parseProductResponse)
        else Left (OffHttpError code (T.take 500 (TE.decodeUtf8Lenient (LBS.toStrict body))))

-- | Open Food Facts answers every lookup with a status: 1 with the
-- product, 0 when the barcode is unknown.
parseProductResponse :: Value -> Either String (Maybe Product)
parseProductResponse = parseEither $ withObject "response" $ \obj -> do
  status <- obj .: "status" :: Parser Int
  case status of
    1 -> Just <$> (parseProduct =<< obj .: "product")
    0 -> pure Nothing
    other -> fail ("unknown Open Food Facts status: " <> show other)

parseProduct :: Object -> Parser Product
parseProduct obj = do
  code        <- Barcode <$> obj .: "code"
  name        <- nonEmpty =<< obj .:? "product_name"
  brands      <- nonEmpty =<< obj .:? "brands"
  quantity    <- nonEmpty =<< obj .:? "quantity"
  serving     <- nonEmpty =<< obj .:? "serving_size"
  ingredients <- nonEmpty =<< obj .:? "ingredients_text"
  nutriments  <- obj .:? "nutriments" .!= mempty
  per100      <- parseNutrients "_100g" nutriments
  perServing  <- parseNutrients "_serving" nutriments
  pure Product
    { offBarcode     = code
    , offName        = name
    , offBrands      = brands
    , offQuantity    = quantity
    , offServingSize = serving
    , offIngredients = ingredients
    , offPer100g     = per100
    , offPerServing  = perServing
    }
  where
    -- The database stores a blank string where nothing was entered.
    nonEmpty (Just t) | not (T.null (T.strip t)) = pure (Just t)
    nonEmpty _ = pure Nothing

parseNutrients :: Text -> Object -> Parser Nutrients
parseNutrients suffix obj = do
  let field name = obj .:? Key.fromText (name <> suffix)
  Nutrients
    <$> field "energy-kcal"
    <*> field "proteins"
    <*> field "fat"
    <*> field "saturated-fat"
    <*> field "carbohydrates"
    <*> field "sugars"
    <*> field "fiber"
    <*> field "sodium"

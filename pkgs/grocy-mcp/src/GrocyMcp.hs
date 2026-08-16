-- | MCP tools over the grocy library, one tool per client operation.
module GrocyMcp
  ( listTools
  , callTool
  ) where

import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Bifunctor (bimap, first)
import Data.ByteString.Lazy qualified as LBS
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (Day)
import Data.Time.Format.ISO8601 (iso8601ParseM)
import MCP.Server.Types
import Money qualified
import Text.Read (readMaybe)

import Grocy
  ( ApiPath (..)
  , GrocyError (..)
  , LocationId (..)
  , ObjectCollection (..)
  , ObjectRef (..)
  , ProductId (..)
  , QuantityUnitId (..)
  , ShoppingLocationId (..)
  )
import Grocy qualified

-- | One delete tool: the object it removes, how its id argument is
-- named, and the constructor that types that id. Both the tool
-- declarations and the dispatcher read this table, so a new deletable
-- collection is one entry.
data Deletion = Deletion
  { deletionTool  :: Text
  , deletionNoun  :: Text
  , deletionIdArg :: Text
  , deletionRef   :: Int -> ObjectRef
  }

deletions :: [Deletion]
deletions =
  [ Deletion "grocy_delete_product" "product" "product_id" (ProductRef . ProductId)
  , Deletion "grocy_delete_location" "location" "location_id" (LocationRef . LocationId)
  , Deletion "grocy_delete_shopping_location" "shopping location" "shopping_location_id"
      (ShoppingLocationRef . ShoppingLocationId)
  , Deletion "grocy_delete_quantity_unit" "quantity unit" "quantity_unit_id"
      (QuantityUnitRef . QuantityUnitId)
  ]

listTools :: [ToolDefinition]
listTools =
  [ tool "grocy_get_products" "List all Grocy products as JSON (id and name)."
      [] []
  , tool "grocy_create_product"
      "Create a Grocy product and return it as JSON. Obtain the ids from\
      \ grocy_ensure_location, grocy_ensure_shopping_location, and\
      \ grocy_find_quantity_unit."
      [ strProp "name" "Product name."
      , intProp "location_id" "Grocy location the product lives in."
      , intProp "quantity_unit_id" "Grocy quantity unit for purchase and stock."
      , intProp "shopping_location_id" "Grocy shopping location the product is bought at."
      ]
      [ "name", "location_id", "quantity_unit_id", "shopping_location_id" ]
  , tool "grocy_add_stock"
      "Record a purchase of an existing product."
      [ intProp "product_id" "Grocy product id, as reported by grocy_get_products."
      , ( "amount"
        , InputSchemaDefinitionProperty
            { propertyType = "number"
            , propertyDescription = "Quantity purchased; fractional for weight-based items."
            }
        )
      , intProp "price_cents" "Total line price in USD cents. Omit when unknown."
      , strProp "purchased_on" "Purchase date, YYYY-MM-DD."
      , strProp "best_before" "Best-before date, YYYY-MM-DD. Omit for never-expires."
      ]
      [ "product_id", "amount", "purchased_on" ]
  , tool "grocy_ensure_location"
      "Return the id of the named Grocy location, creating it if missing."
      [ strProp "name" "Location name." ] [ "name" ]
  , tool "grocy_ensure_shopping_location"
      "Return the id of the named Grocy shopping location, creating it if missing."
      [ strProp "name" "Shopping location name." ] [ "name" ]
  , tool "grocy_find_quantity_unit"
      "Return the id of the named Grocy quantity unit; it must already exist."
      [ strProp "name" "Quantity unit name." ] [ "name" ]
  ]
  <> map deleteTool deletions
  where
    deleteTool deletion = tool
      (deletionTool deletion)
      ("Permanently delete a Grocy " <> deletionNoun deletion
        <> ". This cannot be undone. Grocy refuses with HTTP 400 when the "
        <> deletionNoun deletion <> " cannot be removed.")
      [ intProp (deletionIdArg deletion) ("Id of the " <> deletionNoun deletion <> " to delete.") ]
      [ deletionIdArg deletion ]
    tool name description props reqd = ToolDefinition
      { toolDefinitionName = name
      , toolDefinitionDescription = description
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties = props
          , required = reqd
          }
      , toolDefinitionTitle = Nothing
      }
    strProp name description =
      (name, InputSchemaDefinitionProperty { propertyType = "string", propertyDescription = description })
    intProp name description =
      (name, InputSchemaDefinitionProperty { propertyType = "integer", propertyDescription = description })

callTool :: Grocy.Env -> McpSession IO -> ToolName -> [(ArgumentName, ArgumentValue)] -> IO (Either Error ToolResult)
callTool env _session toolName args = case toolName of
  "grocy_get_products" ->
    run (jsonResult <$> Grocy.getProducts env)
  "grocy_create_product" ->
    run $ case createProductInput args of
      Left err -> pure (Left err)
      Right new -> jsonResult <$> Grocy.createProduct env new
  "grocy_add_stock" ->
    run $ case addStockInput args of
      Left err -> pure (Left err)
      Right (productId, purchase) ->
        bimap ApiFailure (const (stockedMessage productId purchase))
          <$> Grocy.addStock env productId purchase
  "grocy_ensure_location" ->
    run $ withName args $ \name ->
      fmap (idJson "location_id" . unLocationId) <$> Grocy.ensureLocation env name
  "grocy_ensure_shopping_location" ->
    run $ withName args $ \name ->
      fmap (idJson "shopping_location_id" . unShoppingLocationId) <$> Grocy.ensureShoppingLocation env name
  "grocy_find_quantity_unit" ->
    run $ withName args $ \name ->
      fmap (idJson "quantity_unit_id" . unQuantityUnitId) <$> Grocy.findQuantityUnit env name
  _ -> case filter ((== toolName) . deletionTool) deletions of
    (deletion : _) -> run $ case requireInt (deletionIdArg deletion) args of
      Left err -> pure (Left err)
      Right oid ->
        bimap ApiFailure (const (deletedMessage deletion oid))
          <$> Grocy.deleteObject env (deletionRef deletion oid)
    [] -> pure (Left (UnknownTool toolName))
  where
    run :: IO (Either ToolFailure Text) -> IO (Either Error ToolResult)
    run action = do
      result <- action
      pure $ Right $ case result of
        Left failure -> toolError (renderFailure failure)
        Right body   -> toolText body

-- | Everything that turns a call into a tool-level error: a rejected
-- argument or a failure from the Grocy API.
data ToolFailure
  = BadArgument Text
  | ApiFailure GrocyError

renderFailure :: ToolFailure -> Text
renderFailure (BadArgument msg) = msg
renderFailure (ApiFailure err)  = renderGrocyError err

encodeJson :: Aeson.ToJSON a => a -> Text
encodeJson = TE.decodeUtf8Lenient . LBS.toStrict . Aeson.encode

jsonResult :: Aeson.ToJSON a => Either GrocyError a -> Either ToolFailure Text
jsonResult = bimap ApiFailure encodeJson

idJson :: Text -> Int -> Text
idJson key n = encodeJson (Aeson.object [(Key.fromText key, Aeson.toJSON n)])

deletedMessage :: Deletion -> Int -> Text
deletedMessage deletion oid =
  "Deleted " <> deletionNoun deletion <> " " <> T.pack (show oid)

stockedMessage :: ProductId -> Grocy.StockPurchase -> Text
stockedMessage productId purchase =
  "Stocked product " <> T.pack (show (unProductId productId))
  <> ": " <> T.pack (show (Grocy.purchaseAmount purchase))

withName
  :: [(ArgumentName, ArgumentValue)]
  -> (Text -> IO (Either GrocyError Text))
  -> IO (Either ToolFailure Text)
withName args namedOp = case lookup "name" args of
  Nothing   -> pure (Left (BadArgument "name is required"))
  Just name -> first ApiFailure <$> namedOp name

createProductInput :: [(ArgumentName, ArgumentValue)] -> Either ToolFailure Grocy.NewProduct
createProductInput args = do
  name <- requireText "name" args
  locationId <- requireInt "location_id" args
  unitId <- requireInt "quantity_unit_id" args
  shopId <- requireInt "shopping_location_id" args
  pure Grocy.NewProduct
    { Grocy.newProductName             = name
    , Grocy.newProductLocation         = LocationId locationId
    , Grocy.newProductQuantityUnit     = QuantityUnitId unitId
    , Grocy.newProductShoppingLocation = ShoppingLocationId shopId
    }

addStockInput :: [(ArgumentName, ArgumentValue)] -> Either ToolFailure (ProductId, Grocy.StockPurchase)
addStockInput args = do
  productId <- requireInt "product_id" args
  amount <- requireRead "amount" "a number" args :: Either ToolFailure Scientific
  purchasedOn <- requireDay "purchased_on" args
  priceCents <- optionalInt "price_cents" args
  bestBefore <- maybe (Right Grocy.neverExpires) parseDayArg (lookup "best_before" args)
  pure
    ( ProductId productId
    , Grocy.StockPurchase
        { Grocy.purchaseAmount     = amount
        , Grocy.purchasePrice      = fmap (Money.discrete . toInteger) priceCents
        , Grocy.purchasedOn        = purchasedOn
        , Grocy.purchaseBestBefore = bestBefore
        }
    )
  where
    parseDayArg raw = case iso8601ParseM (T.unpack raw) of
      Just day -> Right day
      Nothing  -> Left (BadArgument ("best_before is not a YYYY-MM-DD date: " <> raw))

requireText :: Text -> [(ArgumentName, ArgumentValue)] -> Either ToolFailure Text
requireText key args = case lookup key args of
  Just val -> Right val
  Nothing  -> Left (BadArgument (key <> " is required"))

requireRead :: Read a => Text -> Text -> [(ArgumentName, ArgumentValue)] -> Either ToolFailure a
requireRead key expected args = do
  raw <- requireText key args
  case readMaybe (T.unpack raw) of
    Just val -> Right val
    Nothing  -> Left (BadArgument (key <> " is not " <> expected <> ": " <> raw))

requireInt :: Text -> [(ArgumentName, ArgumentValue)] -> Either ToolFailure Int
requireInt key = requireRead key "an integer"

optionalInt :: Text -> [(ArgumentName, ArgumentValue)] -> Either ToolFailure (Maybe Int)
optionalInt key args = case lookup key args of
  Nothing -> Right Nothing
  Just _  -> Just <$> requireInt key args

requireDay :: Text -> [(ArgumentName, ArgumentValue)] -> Either ToolFailure Day
requireDay key args = do
  raw <- requireText key args
  case iso8601ParseM (T.unpack raw) of
    Just day -> Right day
    Nothing  -> Left (BadArgument (key <> " is not a YYYY-MM-DD date: " <> raw))

renderGrocyError :: GrocyError -> Text
renderGrocyError (GrocyNetworkError path msg) =
  "Could not reach Grocy (" <> unApiPath path <> "): " <> msg
renderGrocyError (GrocyHttpError path code preview) =
  "Grocy " <> unApiPath path <> " returned HTTP " <> T.pack (show code) <> ": " <> preview
renderGrocyError (GrocyParseError path msg) =
  "Failed to parse Grocy response from " <> unApiPath path <> ": " <> msg
renderGrocyError (GrocyObjectNotFound collection name) =
  "Grocy " <> collectionNoun collection <> " not found: " <> name

collectionNoun :: ObjectCollection -> Text
collectionNoun Products          = "product"
collectionNoun Locations         = "location"
collectionNoun ShoppingLocations = "shopping location"
collectionNoun QuantityUnits     = "quantity unit"

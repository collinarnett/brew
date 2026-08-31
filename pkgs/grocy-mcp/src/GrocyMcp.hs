-- | MCP tools over the grocy library, one tool per client operation.
module GrocyMcp
  ( listTools
  , callTool
  ) where

import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
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
  , Barcode (..)
  , GrocyError (..)
  , LocationId (..)
  , ObjectCollection (..)
  , ObjectRef (..)
  , ProductId (..)
  , QuantityUnitId (..)
  , RecipeId (..)
  , ShoppingLocationId (..)
  , UserfieldEntity (..)
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
  , Deletion "grocy_delete_recipe" "recipe" "recipe_id" (RecipeRef . RecipeId)
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
      , intProp "shopping_location_id" "Grocy shopping location the purchase was made at. Omit when unknown."
      , strProp "note" "Free-text note on the stock entry, e.g. the order it arrived in."
      ]
      [ "product_id", "amount", "purchased_on" ]
  , tool "grocy_get_stock"
      "Everything in stock as JSON: product, amount, amount opened, next due date."
      [] []
  , tool "grocy_get_product_details"
      "One product's stock position: amount, opened amount, last price in cents,\
      \ last purchase, next due date, stock and purchase units, location, barcodes."
      [ intProp "product_id" "Grocy product id." ] [ "product_id" ]
  , tool "grocy_search_products"
      "Products whose name contains the term."
      [ strProp "query" "Text to look for in product names." ] [ "query" ]
  , tool "grocy_consume_product"
      "Take an amount of a product out of stock, as used."
      [ intProp "product_id" "Grocy product id."
      , numProp "amount" "Amount to consume, in the product's stock unit."
      ]
      [ "product_id", "amount" ]
  , tool "grocy_add_product_barcode"
      "Link a barcode to a product, such as the package UPC from walmart_get_product,\
      \ so the product can be found again by grocy_find_product_by_barcode."
      [ intProp "product_id" "Grocy product id."
      , strProp "barcode" "The barcode digits."
      , strProp "note" "Where the barcode came from, e.g. walmart."
      ]
      [ "product_id", "barcode" ]
  , tool "grocy_find_product_by_barcode"
      "The product a barcode is linked to, with its stock position, or found: false."
      [ strProp "barcode" "The barcode digits." ] [ "barcode" ]
  , tool "grocy_add_unit_conversion"
      "Declare how many of one unit make one of another, for one product or for all.\
      \ Recipes in a different unit from stock consume through this."
      [ intProp "from_unit_id" "Quantity unit converted from."
      , intProp "to_unit_id" "Quantity unit converted to."
      , numProp "factor" "How many of to_unit one from_unit makes."
      , intProp "product_id" "Product the conversion is specific to. Omit for a general conversion."
      ]
      [ "from_unit_id", "to_unit_id", "factor" ]
  , tool "grocy_create_recipe"
      "Create a recipe and return it as JSON. The description is rendered as HTML\
      \ (use <h3>, <ol><li>, <p>). Add its ingredients with grocy_add_recipe_ingredient."
      [ strProp "name" "Recipe name."
      , intProp "base_servings" "Servings the ingredient amounts are for."
      , strProp "description" "Method text. Optional."
      ]
      [ "name", "base_servings" ]
  , tool "grocy_update_recipe"
      "Change a recipe's name, description (HTML: use <h3>, <ol><li>, <p>) or base\
      \ servings. Fields omitted are left as they are."
      [ intProp "recipe_id" "Grocy recipe id."
      , strProp "name" "New name."
      , strProp "description" "New method text, as HTML."
      , intProp "base_servings" "New base servings."
      ]
      [ "recipe_id" ]
  , tool "grocy_list_recipes"
      "The recipes Grocy holds as JSON (id, name, base servings)."
      [] []
  , tool "grocy_add_recipe_ingredient"
      "Add a product in some amount of some unit to a recipe."
      [ intProp "recipe_id" "Grocy recipe id."
      , intProp "product_id" "Grocy product id."
      , numProp "amount" "Amount of the product."
      , intProp "unit_id" "Quantity unit the amount is in."
      , strProp "note" "Preparation note. Optional."
      ]
      [ "recipe_id", "product_id", "amount", "unit_id" ]
  , tool "grocy_set_recipe_ingredient_amount"
      "Change the amount on one ingredient line, by the ingredient_id that\
      \ grocy_get_recipe_ingredients reports."
      [ intProp "ingredient_id" "Ingredient line id."
      , numProp "amount" "New amount, in the line's unit."
      ]
      [ "ingredient_id", "amount" ]
  , tool "grocy_get_recipe_ingredients"
      "The ingredients of a recipe as JSON."
      [ intProp "recipe_id" "Grocy recipe id." ] [ "recipe_id" ]
  , tool "grocy_recipe_fulfillment"
      "Whether stock covers a recipe, how many products are missing, and its cost."
      [ intProp "recipe_id" "Grocy recipe id." ] [ "recipe_id" ]
  , tool "grocy_consume_recipe"
      "Take every ingredient of a recipe out of stock in one booking."
      [ intProp "recipe_id" "Grocy recipe id." ] [ "recipe_id" ]
  , tool "grocy_set_userfields"
      "Store custom text fields on a product or recipe (e.g. nutrition per serving and\
      \ its source), declaring any field Grocy does not have yet."
      [ strProp "entity" "products or recipes."
      , intProp "object_id" "Id of the product or recipe."
      , strProp "fields" "A JSON object of field name to text value."
      ]
      [ "entity", "object_id", "fields" ]
  , tool "grocy_get_userfields"
      "The custom fields stored on a product or recipe as JSON."
      [ strProp "entity" "products or recipes."
      , intProp "object_id" "Id of the product or recipe."
      ]
      [ "entity", "object_id" ]
  , tool "grocy_ensure_location"
      "Return the id of the named Grocy location, creating it if missing."
      [ strProp "name" "Location name." ] [ "name" ]
  , tool "grocy_ensure_shopping_location"
      "Return the id of the named Grocy shopping location, creating it if missing."
      [ strProp "name" "Shopping location name." ] [ "name" ]
  , tool "grocy_find_quantity_unit"
      "Return the id of the named Grocy quantity unit; it must already exist."
      [ strProp "name" "Quantity unit name." ] [ "name" ]
  , tool "grocy_ensure_quantity_unit"
      "Return the id of the named Grocy quantity unit, creating it if missing\
      \ (e.g. oz, lb, fl oz, cup, tbsp, tsp, can)."
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
    numProp name description =
      (name, InputSchemaDefinitionProperty { propertyType = "number", propertyDescription = description })

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
  "grocy_ensure_quantity_unit" ->
    run $ withName args $ \name ->
      fmap (idJson "quantity_unit_id" . unQuantityUnitId) <$> Grocy.ensureQuantityUnit env name
  "grocy_get_stock" -> run (jsonResult <$> Grocy.getStock env)
  "grocy_get_product_details" -> run $ withArgs (requireInt "product_id" args) $ \pid ->
    jsonResult <$> Grocy.getProductDetails env (ProductId pid)
  "grocy_search_products" -> run $ withArgs (requireText "query" args) $ \q ->
    jsonResult <$> Grocy.searchProducts env q
  "grocy_consume_product" -> run $ withArgs ((,) <$> requireInt "product_id" args <*> requireRead "amount" "a number" args) $ \(pid, amount) ->
    bimap ApiFailure (const ("Consumed " <> T.pack (show (amount :: Scientific)) <> " of product " <> T.pack (show pid)))
      <$> Grocy.consumeProduct env (ProductId pid) amount
  "grocy_add_product_barcode" -> run $ withArgs ((,) <$> requireInt "product_id" args <*> requireText "barcode" args) $ \(pid, code) ->
    bimap ApiFailure (const ("Linked barcode " <> code <> " to product " <> T.pack (show pid)))
      <$> Grocy.addProductBarcode env (ProductId pid) (Barcode code) (lookup "note" args)
  "grocy_find_product_by_barcode" -> run $ withArgs (requireText "barcode" args) $ \code ->
    fmap foundJson <$> Grocy.findProductByBarcode env (Barcode code) >>= pure . first ApiFailure
  "grocy_add_unit_conversion" -> run $ withArgs (conversionInput args) $ \conv ->
    bimap ApiFailure (const "Unit conversion added") <$> Grocy.addUnitConversion env conv
  "grocy_create_recipe" -> run $ withArgs (recipeInput args) $ \new ->
    jsonResult <$> Grocy.createRecipe env new
  "grocy_list_recipes" -> run (jsonResult <$> Grocy.getRecipes env)
  "grocy_update_recipe" -> run $ withArgs ((,) <$> requireInt "recipe_id" args <*> optionalInt "base_servings" args) $ \(rid, servings) ->
    bimap ApiFailure (const ("Updated recipe " <> T.pack (show rid)))
      <$> Grocy.updateRecipe env (RecipeId rid) Grocy.RecipeChanges
            { Grocy.changeName         = lookup "name" args
            , Grocy.changeDescription  = lookup "description" args
            , Grocy.changeBaseServings = servings
            }
  "grocy_add_recipe_ingredient" -> run $ withArgs (ingredientInput args) $ \(rid, ingredient) ->
    bimap ApiFailure (const ("Added ingredient to recipe " <> T.pack (show (unRecipeId rid))))
      <$> Grocy.addIngredient env rid ingredient
  "grocy_set_recipe_ingredient_amount" -> run $ withArgs ((,) <$> requireInt "ingredient_id" args <*> requireRead "amount" "a number" args) $ \(iid, amount) ->
    bimap ApiFailure (const ("Set ingredient " <> T.pack (show iid) <> " to " <> T.pack (show (amount :: Scientific))))
      <$> Grocy.setIngredientAmount env (Grocy.IngredientId iid) amount
  "grocy_get_recipe_ingredients" -> run $ withArgs (requireInt "recipe_id" args) $ \rid ->
    jsonResult <$> Grocy.getIngredients env (RecipeId rid)
  "grocy_recipe_fulfillment" -> run $ withArgs (requireInt "recipe_id" args) $ \rid ->
    jsonResult <$> Grocy.recipeFulfillment env (RecipeId rid)
  "grocy_consume_recipe" -> run $ withArgs (requireInt "recipe_id" args) $ \rid ->
    bimap ApiFailure (const ("Consumed recipe " <> T.pack (show rid))) <$> Grocy.consumeRecipe env (RecipeId rid)
  "grocy_set_userfields" -> run $ withArgs (userfieldsInput args) $ \(entity, oid, fields) -> do
    declared <- traverse (Grocy.ensureUserfield env entity . fst) fields
    case sequence_ declared of
      Left err -> pure (Left (ApiFailure err))
      Right () -> bimap ApiFailure (const ("Stored " <> T.pack (show (length fields)) <> " fields"))
        <$> Grocy.setUserfields env entity oid fields
  "grocy_get_userfields" -> run $ withArgs ((,) <$> requireEntity args <*> requireInt "object_id" args) $ \(entity, oid) ->
    jsonResult . fmap (Aeson.object . map (\(k, v) -> Key.fromText k Aeson..= v)) <$> Grocy.getUserfields env entity oid
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

-- | Run an operation once its arguments parsed.
withArgs :: Either ToolFailure a -> (a -> IO (Either ToolFailure Text)) -> IO (Either ToolFailure Text)
withArgs parsedArgs op = either (pure . Left) op parsedArgs

foundJson :: Maybe Grocy.ProductDetails -> Text
foundJson Nothing  = encodeJson (Aeson.object [ "found" Aeson..= False ])
foundJson (Just d) = encodeJson (Aeson.object [ "found" Aeson..= True, "product" Aeson..= d ])

conversionInput :: [(ArgumentName, ArgumentValue)] -> Either ToolFailure Grocy.UnitConversion
conversionInput args = do
  from <- requireInt "from_unit_id" args
  to <- requireInt "to_unit_id" args
  factor <- requireRead "factor" "a number" args
  product_ <- optionalInt "product_id" args
  pure Grocy.UnitConversion
    { Grocy.ucFrom    = QuantityUnitId from
    , Grocy.ucTo      = QuantityUnitId to
    , Grocy.ucFactor  = factor
    , Grocy.ucProduct = ProductId <$> product_
    }

recipeInput :: [(ArgumentName, ArgumentValue)] -> Either ToolFailure Grocy.NewRecipe
recipeInput args = do
  name <- requireText "name" args
  servings <- requireInt "base_servings" args
  pure Grocy.NewRecipe
    { Grocy.newRecipeName         = name
    , Grocy.newRecipeDescription  = lookup "description" args
    , Grocy.newRecipeBaseServings = servings
    }

ingredientInput :: [(ArgumentName, ArgumentValue)] -> Either ToolFailure (RecipeId, Grocy.Ingredient)
ingredientInput args = do
  rid <- requireInt "recipe_id" args
  pid <- requireInt "product_id" args
  amount <- requireRead "amount" "a number" args
  unit <- requireInt "unit_id" args
  pure
    ( RecipeId rid
    , Grocy.Ingredient
        { Grocy.ingredientId      = Nothing
        , Grocy.ingredientProduct = ProductId pid
        , Grocy.ingredientAmount  = amount
        , Grocy.ingredientUnit    = QuantityUnitId unit
        , Grocy.ingredientNote    = lookup "note" args
        }
    )

requireEntity :: [(ArgumentName, ArgumentValue)] -> Either ToolFailure UserfieldEntity
requireEntity args = do
  raw <- requireText "entity" args
  case raw of
    "products" -> Right ProductFields
    "recipes"  -> Right RecipeFields
    other      -> Left (BadArgument ("entity must be products or recipes, got: " <> other))

userfieldsInput :: [(ArgumentName, ArgumentValue)] -> Either ToolFailure (UserfieldEntity, Int, [(Text, Text)])
userfieldsInput args = do
  entity <- requireEntity args
  oid <- requireInt "object_id" args
  raw <- requireText "fields" args
  fields <- case Aeson.eitherDecodeStrict (TE.encodeUtf8 raw) of
    Right (Aeson.Object obj) -> traverse textValue (KM.toList obj)
    Right _ -> Left (BadArgument "fields must be a JSON object")
    Left err -> Left (BadArgument ("fields is not JSON: " <> T.pack err))
  pure (entity, oid, fields)
  where
    textValue (k, Aeson.String v) = Right (Key.toText k, v)
    textValue (k, Aeson.Number n) = Right (Key.toText k, T.pack (show n))
    textValue (k, other) = Left (BadArgument ("field " <> Key.toText k <> " must be text, got: " <> T.pack (show other)))

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
  shopId <- optionalInt "shopping_location_id" args
  bestBefore <- maybe (Right Grocy.neverExpires) parseDayArg (lookup "best_before" args)
  pure
    ( ProductId productId
    , Grocy.StockPurchase
        { Grocy.purchaseAmount           = amount
        , Grocy.purchasePrice            = fmap (Money.discrete . toInteger) priceCents
        , Grocy.purchasedOn              = purchasedOn
        , Grocy.purchaseBestBefore       = bestBefore
        , Grocy.purchaseShoppingLocation = ShoppingLocationId <$> shopId
        , Grocy.purchaseNote             = lookup "note" args
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
collectionNoun Recipes           = "recipe"
collectionNoun RecipePositions   = "recipe ingredient"
collectionNoun ProductBarcodes   = "product barcode"
collectionNoun UnitConversions   = "unit conversion"
collectionNoun Userfields        = "userfield"

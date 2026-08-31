-- | MCP tools over the openfoodfacts library.
module NutritionMcp
  ( listTools
  , callTool
  ) where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import MCP.Server.Types

import OpenFoodFacts qualified
import OpenFoodFacts (Barcode (..), OffError (..))

listTools :: [ToolDefinition]
listTools =
  [ ToolDefinition
      { toolDefinitionName = "nutrition_by_barcode"
      , toolDefinitionDescription =
          "Look a package barcode (UPC-A or EAN-13) up in Open Food Facts\
          \ and return the label: name, brand, package quantity, serving\
          \ size, ingredient statement, and nutrients per 100 g and per\
          \ serving (calories in kcal, everything else in grams). A\
          \ nutrient the database lacks is null, never zero. An unknown\
          \ barcode answers found: false."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ( "barcode"
                , InputSchemaDefinitionProperty
                    { propertyType = "string"
                    , propertyDescription = "The barcode digits, e.g. the upc from walmart_get_product."
                    }
                )
              ]
          , required = [ "barcode" ]
          }
      , toolDefinitionTitle = Just "Nutrition by barcode"
      }
  ]

callTool :: OpenFoodFacts.Env -> McpSession IO -> ToolName -> [(ArgumentName, ArgumentValue)] -> IO (Either Error ToolResult)
callTool env _session toolName args = case toolName of
  "nutrition_by_barcode" -> case lookup "barcode" args of
    Nothing -> pure (Right (toolError "barcode is required"))
    Just raw
      | T.null digits -> pure (Right (toolError ("barcode must be digits, got: " <> raw)))
      | otherwise -> do
          result <- OpenFoodFacts.lookupProduct env (Barcode digits)
          pure $ Right $ case result of
            Left err -> toolError (renderError err)
            Right Nothing -> toolText (encodeText (Aeson.object [ "found" Aeson..= False, "barcode" Aeson..= digits ]))
            Right (Just p) -> toolText (encodeText (Aeson.object [ "found" Aeson..= True, "product" Aeson..= p ]))
      where digits = T.filter (`elem` ['0' .. '9']) raw
  _ -> pure (Left (UnknownTool toolName))

encodeText :: Aeson.Value -> Text
encodeText = TE.decodeUtf8Lenient . LBS.toStrict . Aeson.encode

renderError :: OffError -> Text
renderError (OffNetworkError msg) = "Could not reach Open Food Facts: " <> msg
renderError (OffHttpError code body) = "Open Food Facts returned HTTP " <> T.pack (show code) <> ": " <> body
renderError (OffParseError err) = "Could not parse the Open Food Facts response: " <> T.pack err

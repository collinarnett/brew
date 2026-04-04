# grocy-client

Generated Haskell client for the [Grocy](https://grocy.info) REST API, covering 66 typed endpoints across stock management, recipes, chores, shopping lists, and user management.

Generated from Grocy's OpenAPI 3.1.0 spec using [openapi3-code-generator](https://github.com/Haskell-OpenAPI-Code-Generator/Haskell-OpenAPI-Client-Code-Generator).

## Usage

```haskell
import GrocyClient.Common (Configuration (..), runWithConfiguration)
import GrocyClient.Configuration (defaultConfiguration)
import GrocyClient.SecuritySchemes (apiKeyInHeaderAuthenticationSecurityScheme)
import qualified GrocyClient

main :: IO ()
main = do
  let config = defaultConfiguration
        { configBaseURL = "https://grocy.example.com"
        , configSecurityScheme = apiKeyInHeaderAuthenticationSecurityScheme "your-key"
        }
  resp <- runWithConfiguration config GrocyClient.get_stock
  print resp
```

Each operation has two variants: one that runs in `ClientT m` (for sequencing multiple calls with a shared configuration) and one that takes an explicit `Configuration` (for standalone calls). Raw `ByteString` variants are also available for operations where you want to handle parsing yourself.

## Authentication

Pass your Grocy API key via `apiKeyInHeaderAuthenticationSecurityScheme`. Create API keys in the Grocy web UI under Settings > API Keys.

## Excluded endpoints

Seven generic entity CRUD endpoints (`/objects/{entity}`, `/userfields/{entity}`) are excluded because Grocy's OpenAPI spec references `ExposedEntity` parameter schemas that aren't defined. These endpoints work fine via the API but can't be typed by the code generator. Use the raw HTTP functions from `GrocyClient.Common` if you need them.

## Regenerating

When Grocy updates its API, regenerate from the spec:

```
nix build -f pkgs/grocy-client/generate.nix -o /tmp/grocy-gen
rm -rf pkgs/grocy-client/src && cp -r /tmp/grocy-gen/{src,grocy-client.cabal} pkgs/grocy-client/
```

The `generate.nix` derivation pulls the spec from `pkgs.grocy.src`, so the generated client automatically matches the Grocy version in nixpkgs. The codegen tool is pinned to a specific commit that includes the GHC compatibility fix.

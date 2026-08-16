# grocy

Hand-written client for the [Grocy](https://grocy.info) v4 REST API,
covering the slice walmart-grocy-import needs: product listing and
creation, stock purchases, and named-object lookup/creation for
locations, shopping locations, and quantity units.

```haskell
import qualified Grocy

main :: IO ()
main = do
  env <- Grocy.newEnv (Grocy.BaseUrl "https://grocy.example.com") (Grocy.ApiKey "...")
  Right products <- Grocy.getProducts env
  print products
```

Ids are distinct newtypes (`ProductId`, `LocationId`, `ShoppingLocationId`,
`QuantityUnitId`) so they cannot be swapped at a call site. Every operation
returns `Either GrocyError`; nothing throws for API-level failures.

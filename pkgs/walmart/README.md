# walmart

Haskell client for Walmart's GraphQL API. Typed access to order history and per-item order details including prices, quantities, and sales unit types.

```haskell
import qualified Walmart
import BrowserCookies (getFirefoxCookies, defaultConfig)

main :: IO ()
main = do
  Right cookies <- getFirefoxCookies defaultConfig ".walmart.com"
  env <- Walmart.newEnv cookies
  Right orders <- Walmart.getOrders env Nothing 10
  Right detail <- Walmart.getOrder env (head orders)
  mapM_ print (Walmart.woItems detail)
```

## API

The library exposes two operations through an opaque `Env`:

- `newEnv :: CookieJar -> IO Env` creates a client from Walmart session cookies. Manages its own HTTP connection pool.
- `getOrders :: Env -> Maybe UTCTime -> Int -> IO (Either WalmartError [OrderSummary])` fetches order summaries, optionally filtered by a start time and limited to N results.
- `getOrder :: Env -> OrderSummary -> IO (Either WalmartError WalmartOrder)` fetches full order details including per-item prices.

## Types

Each `WalmartItem` carries:
- `wiName` — product name
- `wiQuantity` — amount purchased (`Scientific`, handles weight-based items)
- `wiLinePrice` — total line price as `Discrete "USD" "cent"` from `safe-money`
- `wiUsItemId` — Walmart's item identifier
- `wiSalesUnitType` — `Each`, `EachWeight`, or `PackWeight`

## Authentication

Walmart's API requires session cookies from a logged-in browser. The `browser-cookies` package handles extraction. Cookies expire periodically; if you get `WalmartAccessDenied` errors, log into walmart.com in Firefox to refresh them.

## Endpoint management

Walmart uses GraphQL persisted queries with hashes that rotate when they deploy. The endpoint URLs are compiled into the library as constants. When they rotate (you'll see `WalmartHashRotated` errors), use `walmart-extractor` to discover the new hashes and rebuild.

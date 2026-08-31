# walmart

Client for the GraphQL gateways behind walmart.com, authenticated with
the local Firefox session.

```haskell
Right cookies <- getFirefoxCookies ".walmart.com"
catalogPath   <- Walmart.defaultCatalogPath
Right env     <- Walmart.newEnv cookies catalogPath seeds
Right result  <- Walmart.searchProducts env query
```

- `getOrders` / `getOrderDetails` — order history and per-order items
  with prices.
- `searchProducts` — catalogue search, optionally restricted to a
  category, returning products alongside the categories Walmart offers
  to narrow the same search.
- `findStores` — stores around a postal code, nearest first.
- `getCart` — the session's cart and the store it is assorted against.
- `getSlots` — delivery or pickup slots offered to the cart, by day.
- `probe` — any catalogued operation with hand-built variables, for
  learning a gateway's expectations before modelling it.

## Endpoint hashes are discovered, never written down

Walmart's gateways address each operation by the hash of a persisted
query document, and those hashes change with every frontend release. No
hash appears in this library: `Endpoint` has no exported constructor, so
the only way to obtain one is `resolve`, which needs an entry in a
`Catalog`.

`Walmart.Discovery` fills that catalog. Walmart's homepage names the
asset base its own scripts load from; the base leads to the build
manifest; the manifest and the page together name the chunks; the chunks
carry the hashes. Every step after the first reads an unauthenticated
CDN, and none of it needs a browser.

A request that meets Walmart's 400 for a retired hash refreshes the
catalog and runs once more, so rotation costs a repeated request rather
than a release of this client. Refreshes are recorded as notices, which
callers drain with `takeNotices`.

Discovery only sees what Walmart ships to browsers. `getOrder` is
registered server-side and never appears in a bundle, so hashes for
operations like it are supplied by configuration and merged underneath
whatever discovery finds — a refresh can only add and update, never
drop.

## Tests

`test/corpus` holds Walmart documents captured from five frontend builds
between May 2025 and August 2026, plus the two ways Walmart refuses a
request. The parsers are written against one build and must handle the
rest unseen, which is what stops them fitting a single release. The
refusals are there so that "found nothing" stays distinguishable from
"invented something".

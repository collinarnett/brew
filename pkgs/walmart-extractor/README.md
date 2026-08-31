# walmart-extractor

Maintenance CLI for the persisted query catalog the `walmart` library
resolves endpoints against.

```
walmart-extractor refresh [catalog-file]   # scan the current build, update the catalog
walmart-extractor show [catalog-file]      # list what is known, with where each hash came from
walmart-extractor probe <operation> <gateway> <query|mutation> <variables.json> [path-suffix]
                                           # send one catalogued operation with the
                                           # Firefox session and print the response
```

The catalog defaults to `$XDG_STATE_HOME/walmart/catalog.json`.

`walmart-mcp` refreshes on its own whenever Walmart retires a hash, so
this is for running that on purpose and for seeing the result. Neither
needs a browser: discovery reads Walmart's homepage for the current
build coordinates and then an unauthenticated CDN for the rest.

# openfoodfacts

Client for the Open Food Facts product database, keyed by barcode.

```haskell
env <- OpenFoodFacts.newEnv (UserAgent "my-app/1.0 (contact)")
Right found <- OpenFoodFacts.lookupProduct env (Barcode "078742351865")
```

`lookupProduct` returns `Nothing` for a barcode the database has never
seen. Every nutrient is optional: the database holds what someone
transcribed from the label, and nothing more. Amounts are grams, energy
is kilocalories, for 100 g and for one serving.

Open Food Facts asks each client to identify itself with a User-Agent,
which `newEnv` takes.

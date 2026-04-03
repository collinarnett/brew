{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Aeson.Key
import Data.Scientific (scientific)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (UTCTime)
import Data.Time.Format.ISO8601 (iso8601ParseM)
import Test.QuickCheck
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck (testProperty)

import WalmartGrocy.Extractor (collectAll, parseHashPair, parseScriptUrls)
import WalmartGrocy.JSON (parseGrocyProducts, parseOrderSummaries, parseWalmartOrder)
import WalmartGrocy.Reconcile (bestMatch, deduplicateBy, reconcile)
import WalmartGrocy.Types

-- Helpers

mkItem :: Text -> WalmartItem
mkItem name = WalmartItem
  { wiName          = name
  , wiQuantity      = scientific 1 0
  , wiLinePrice     = Just (scientific 597 (-2))
  , wiUsItemId      = UsItemId "123"
  , wiSalesUnitType = Each
  }

mkProduct :: Int -> Text -> GrocyProduct
mkProduct pid name = GrocyProduct (ProductId pid) name

mkOrder :: [WalmartItem] -> WalmartOrder
mkOrder items = WalmartOrder
  { woOrderId   = OrderId "test-order"
  , woOrderDate = parseTime "2026-03-22T14:00:00Z"
  , woItems     = items
  }

parseTime :: String -> UTCTime
parseTime s = case iso8601ParseM s of
  Just t  -> t
  Nothing -> error ("bad test time: " <> s)

-- Generators

newtype AlphaText = AlphaText Text deriving stock (Show)
instance Arbitrary AlphaText where
  arbitrary = AlphaText . T.pack <$> listOf1 (elements (['a'..'z'] <> ['A'..'Z'] <> [' ']))

newtype HexHash = HexHash Text deriving stock (Show)
instance Arbitrary HexHash where
  arbitrary = HexHash . T.pack <$> vectorOf 64 (elements (['0'..'9'] <> ['a'..'f']))

main :: IO ()
main = defaultMain $ testGroup "walmart-grocy-import"
  [ reconcileTests
  , jsonTests
  , extractorParserTests
  , propertyTests
  , adversarialTests
  ]

-- ================================================================
-- Unit tests
-- ================================================================

reconcileTests :: TestTree
reconcileTests = testGroup "Reconcile"
  [ testCase "exact match" $
      bestMatch "Fresh Banana, Each" [mkProduct 1 "Fresh Banana, Each"]
        @?= Just (mkProduct 1 "Fresh Banana, Each")

  , testCase "fuzzy match" $
      case bestMatch "Great Value Milk Gallon 128 fl oz"
             [mkProduct 1 "Great Value Milk, Gallon, 128 fl oz"] of
        Just _  -> pure ()
        Nothing -> assertFailure "expected a fuzzy match"

  , testCase "no match for unrelated items" $
      bestMatch "Toilet Paper Extra Large" [mkProduct 1 "Bananas"]
        @?= Nothing

  , testCase "no match on empty product list" $
      bestMatch "anything" [] @?= Nothing

  , testCase "reconcile creates StockExisting for matched items" $ do
      let plan = reconcile [mkProduct 1 "Bananas"] (mkOrder [mkItem "Bananas"])
      length (ipActions plan) @?= 1
      assertBool "expected StockExisting" $ case ipActions plan of
        [StockExisting _ _] -> True
        _                   -> False

  , testCase "reconcile creates CreateAndStock for unmatched items" $ do
      let plan = reconcile [mkProduct 1 "Milk"] (mkOrder [mkItem "Exotic Dragon Fruit"])
      assertBool "expected CreateAndStock" $ case ipActions plan of
        [CreateAndStock _] -> True
        _                  -> False

  , testCase "deduplicateBy removes duplicates" $
      deduplicateBy id ["a", "b", "a", "c", "b" :: Text]
        @?= ["a", "b", "c"]

  , testCase "deduplicateBy on empty" $
      deduplicateBy (id :: Text -> Text) [] @?= []
  ]

jsonTests :: TestTree
jsonTests = testGroup "JSON"
  [ testCase "parse PurchaseHistoryV2 response" $ do
      let json = Aeson.object
            [ "data" Aeson..= Aeson.object
                [ "orderHistoryV2" Aeson..= Aeson.object
                    [ "orderGroups" Aeson..=
                        [ Aeson.object
                            [ "orderId"   Aeson..= ("123" :: Text)
                            , "type"      Aeson..= ("GLASS" :: Text)
                            , "itemCount" Aeson..= (3 :: Int)
                            , "items"     Aeson..= ([] :: [Aeson.Value])
                            ]
                        ]
                    ]
                ]
            ]
      case parseOrderSummaries json of
        Right [s] -> do
          osOrderId s @?= OrderId "123"
          osItemCount s @?= 3
          osIsInStore s @?= False
        Right xs -> assertFailure ("expected 1 summary, got " <> show (length xs))
        Left err -> assertFailure err

  , testCase "recognize IN_STORE orders" $ do
      let json = Aeson.object
            [ "data" Aeson..= Aeson.object
                [ "orderHistoryV2" Aeson..= Aeson.object
                    [ "orderGroups" Aeson..=
                        [ Aeson.object
                            [ "orderId"   Aeson..= ("456" :: Text)
                            , "type"      Aeson..= ("IN_STORE" :: Text)
                            , "itemCount" Aeson..= (1 :: Int)
                            , "items"     Aeson..= ([] :: [Aeson.Value])
                            ]
                        ]
                    ]
                ]
            ]
      case parseOrderSummaries json of
        Right [s] -> osIsInStore s @?= True
        _         -> assertFailure "parse failed"

  , testCase "parse getOrder with aliased groups key" $ do
      let json = mkGetOrderJson "groups_2101"
      case parseWalmartOrder json of
        Right order -> do
          unOrderId (woOrderId order) @?= "ord1"
          length (woItems order) @?= 1
          wiName (listHead (woItems order)) @?= "Bananas"
          wiSalesUnitType (listHead (woItems order)) @?= EachWeight
          wiQuantity (listHead (woItems order)) @?= 2
        Left err -> assertFailure err

  , testCase "getOrder fails on missing groups" $ do
      let json = Aeson.object
            [ "data" Aeson..= Aeson.object
                [ "order" Aeson..= Aeson.object
                    [ "id"        Aeson..= ("ord2" :: Text)
                    , "orderDate" Aeson..= ("2026-01-01T00:00:00Z" :: Text)
                    ]
                ]
            ]
      assertBool "expected Left" $ isLeft (parseWalmartOrder json)

  , testCase "parse Grocy products" $ do
      let json = Aeson.toJSON
            [ Aeson.object ["id" Aeson..= (1 :: Int), "name" Aeson..= ("Milk" :: Text)]
            , Aeson.object ["id" Aeson..= (2 :: Int), "name" Aeson..= ("Bread" :: Text)]
            ]
      case parseGrocyProducts json of
        Right ps -> do
          length ps @?= 2
          gpName (listHead ps) @?= "Milk"
        Left err -> assertFailure err
  ]

extractorParserTests :: TestTree
extractorParserTests = testGroup "Extractor parsers"
  [ testCase "extract script URLs from HTML" $ do
      let html = T.unlines
            [ "<script src=\"https://i5.walmartimages.com/chunk-abc.js\"></script>"
            , "<script src=\"/local.js\"></script>"
            , "<script src=\"https://i5.walmartimages.com/other-def.js\"></script>"
            ]
      let urls = parseScriptUrls html
      length urls @?= 2
      listHead urls @?= "https://i5.walmartimages.com/chunk-abc.js"

  , testCase "extract hash pairs from JS" $ do
      let js = "blah name:\"PurchaseHistoryV2\",hash:\"a7067e4c7c36457fdef25b48d8c1ab5574f2e5f64580cdd5b1202b32c39928f6\" more"
      let pairs = collectAll parseHashPair js
      length pairs @?= 1
      fst (listHead pairs) @?= "PurchaseHistoryV2"

  , testCase "no script URLs in empty HTML" $
      parseScriptUrls "" @?= []

  , testCase "no hash pairs in random text" $
      collectAll parseHashPair "no hashes here" @?= []
  ]

-- ================================================================
-- Property tests
-- ================================================================

propertyTests :: TestTree
propertyTests = testGroup "Properties"
  [ testProperty "deduplicateBy preserves first occurrence" $
      \(xs :: [Int]) ->
        let deduped = deduplicateBy id xs
            firstOccurrence x = listHead (filter (== x) xs)
        in all (\x -> firstOccurrence x == x) deduped

  , testProperty "deduplicateBy produces unique elements" $
      \(xs :: [Int]) ->
        let deduped = deduplicateBy id xs
        in length deduped == length (nub deduped)

  , testProperty "deduplicateBy is idempotent" $
      \(xs :: [Int]) ->
        let deduped = deduplicateBy id xs
        in deduplicateBy id deduped == deduped

  , testProperty "reconcile produces one action per item" $
      \(xs :: NonEmptyList String) ->
        let items = map (mkItem . T.pack) (getNonEmpty xs)
            plan = reconcile [] (mkOrder items)
        in length (ipActions plan) == length items

  , testProperty "no products means all CreateAndStock" $
      \(xs :: NonEmptyList String) ->
        let items = map (mkItem . T.pack) (getNonEmpty xs)
            plan = reconcile [] (mkOrder items)
        in all isCreate (ipActions plan)

  , testProperty "hash parser roundtrips valid pairs" $
      \(AlphaText name, HexHash hash) ->
        let input = "prefix name:\"" <> name <> "\",hash:\"" <> hash <> "\" suffix"
        in collectAll parseHashPair input == [(name, hash)]
  ]

-- ================================================================
-- Adversarial tests
-- ================================================================

adversarialTests :: TestTree
adversarialTests = testGroup "Adversarial"
  [ testGroup "JSON injection / malformed input" $
    [ testCase "order with null data envelope" $
        assertBool "expected Left" $ isLeft $
          parseOrderSummaries (Aeson.object ["data" Aeson..= Aeson.Null])

    , testCase "order with data.orderHistoryV2 = null" $
        assertBool "expected Left" $ isLeft $
          parseOrderSummaries (Aeson.object
            [ "data" Aeson..= Aeson.object
                [ "orderHistoryV2" Aeson..= Aeson.Null ]
            ])

    , testCase "order with empty response body" $
        assertBool "expected Left" $ isLeft $
          parseOrderSummaries (Aeson.object [])

    , testCase "getOrder with data.order = null" $
        assertBool "expected Left" $ isLeft $
          parseWalmartOrder (Aeson.object
            [ "data" Aeson..= Aeson.object
                [ "order" Aeson..= Aeson.Null ]
            ])

    , testCase "getOrder with wrong type for groups" $
        assertBool "expected Left" $ isLeft $
          parseWalmartOrder (Aeson.object
            [ "data" Aeson..= Aeson.object
                [ "order" Aeson..= Aeson.object
                    [ "id" Aeson..= ("x" :: Text)
                    , "orderDate" Aeson..= ("2026-01-01T00:00:00Z" :: Text)
                    , "groups_2101" Aeson..= ("not an array" :: Text)
                    ]
                ]
            ])

    , testCase "getOrder with empty groups array" $
        assertBool "expected Left" $ isLeft $
          parseWalmartOrder (Aeson.object
            [ "data" Aeson..= Aeson.object
                [ "order" Aeson..= Aeson.object
                    [ "id" Aeson..= ("x" :: Text)
                    , "orderDate" Aeson..= ("2026-01-01T00:00:00Z" :: Text)
                    , "groups_2101" Aeson..= ([] :: [Aeson.Value])
                    ]
                ]
            ])

    , testCase "getOrder group with items missing productInfo" $
        assertBool "expected Left" $ isLeft $
          parseWalmartOrder (Aeson.object
            [ "data" Aeson..= Aeson.object
                [ "order" Aeson..= Aeson.object
                    [ "id" Aeson..= ("x" :: Text)
                    , "orderDate" Aeson..= ("2026-01-01T00:00:00Z" :: Text)
                    , "groups_9999" Aeson..=
                        [ Aeson.object [ "items" Aeson..=
                            [ Aeson.object
                                [ "quantity" Aeson..= (1 :: Int) ]
                            ]]
                        ]
                    ]
                ]
            ])

    , testCase "item with unknown salesUnitType" $
        assertBool "expected Left" $ isLeft $
          parseWalmartOrder (mkGetOrderJsonWith "UNKNOWN_TYPE")

    , testCase "Grocy products with missing id field" $
        assertBool "expected Left" $ isLeft $
          parseGrocyProducts (Aeson.toJSON
            [Aeson.object ["name" Aeson..= ("Milk" :: Text)]])

    , testCase "Grocy products with missing name field" $
        assertBool "expected Left" $ isLeft $
          parseGrocyProducts (Aeson.toJSON
            [Aeson.object ["id" Aeson..= (1 :: Int)]])

    , testCase "Grocy products: not an array" $
        assertBool "expected Left" $ isLeft $
          parseGrocyProducts (Aeson.object ["foo" Aeson..= (1 :: Int)])
    ]

  , testGroup "Parser edge cases" $
    [ testCase "hash with uppercase hex is rejected" $
        collectAll parseHashPair
          "name:\"Foo\",hash:\"A7067E4C7C36457FDEF25B48D8C1AB5574F2E5F64580CDD5B1202B32C39928F6\""
          @?= []

    , testCase "hash with 63 chars is rejected" $
        collectAll parseHashPair
          "name:\"Foo\",hash:\"a7067e4c7c36457fdef25b48d8c1ab5574f2e5f64580cdd5b1202b32c39928f\""
          @?= []

    , testCase "script URL without .js extension is skipped" $
        parseScriptUrls "<script src=\"https://i5.walmartimages.com/chunk.css\"></script>"
          @?= []

    , testCase "multiple hashes in one JS chunk" $ do
        let js = T.concat
              [ "name:\"Op1\",hash:\"" <> T.replicate 64 "a" <> "\""
              , " other stuff "
              , "name:\"Op2\",hash:\"" <> T.replicate 64 "b" <> "\""
              ]
        let pairs = collectAll parseHashPair js
        length pairs @?= 2
        fst (listHead pairs) @?= "Op1"

    , testCase "parser survives megabytes of garbage" $ do
        let garbage = T.replicate 1000000 "x"
        parseScriptUrls garbage @?= []
        collectAll parseHashPair garbage @?= []
    ]

  , testGroup "Reconcile edge cases" $
    [ testCase "all items match the same product" $ do
        let products = [mkProduct 1 "Bananas"]
            order = mkOrder [mkItem "Bananas", mkItem "Bananas", mkItem "Bananas"]
            plan = reconcile products order
        length (ipActions plan) @?= 3
        assertBool "all should match" $ all isStockExisting (ipActions plan)

    , testCase "empty order produces empty plan" $ do
        let plan = reconcile [mkProduct 1 "X"] (mkOrder [])
        ipActions plan @?= []

    , testCase "unicode product names match" $
        case bestMatch "Boursin® Hot Honey" [mkProduct 1 "Boursin® Hot Honey"] of
          Just _  -> pure ()
          Nothing -> assertFailure "unicode match failed"

    , testCase "very long product names don't crash" $ do
        let longName = T.replicate 10000 "Great Value "
        -- Just verify it terminates without exception; fuzzy libs
        -- may return Nothing for very long strings and that's fine.
        case bestMatch longName [mkProduct 1 longName] of
          Just _  -> pure ()
          Nothing -> pure ()
    ]

  , testGroup "Property: adversarial" $
    [ testProperty "reconcile never crashes on arbitrary text" $
        \(xs :: [String]) ->
          let items = map (mkItem . T.pack) xs
              plan = reconcile [] (mkOrder items)
          in length (ipActions plan) == length items

    , testProperty "deduplicateBy result is always a subsequence" $
        \(xs :: [Int]) ->
          let deduped = deduplicateBy id xs
          in isSubsequenceOf deduped xs

    , testProperty "parser never crashes on arbitrary bytes" $
        \(s :: String) ->
          let t = T.pack s
          in parseScriptUrls t `seq` collectAll parseHashPair t `seq` True
    ]
  ]

-- ================================================================
-- Utilities
-- ================================================================

listHead :: [a] -> a
listHead (x : _) = x
listHead []      = error "listHead: empty list in test"

isLeft :: Either a b -> Bool
isLeft (Left _)  = True
isLeft (Right _) = False

isCreate :: Action -> Bool
isCreate (CreateAndStock _) = True
isCreate _                  = False

isStockExisting :: Action -> Bool
isStockExisting (StockExisting _ _) = True
isStockExisting _                   = False

nub :: Eq a => [a] -> [a]
nub [] = []
nub (x : xs) = x : nub (filter (/= x) xs)

isSubsequenceOf :: Eq a => [a] -> [a] -> Bool
isSubsequenceOf [] _ = True
isSubsequenceOf _ [] = False
isSubsequenceOf (x : xs) (y : ys)
  | x == y    = isSubsequenceOf xs ys
  | otherwise = isSubsequenceOf (x : xs) ys

-- | Build a getOrder JSON with a configurable groups key name.
mkGetOrderJson :: Text -> Aeson.Value
mkGetOrderJson groupsKey = Aeson.object
  [ "data" Aeson..= Aeson.object
      [ "order" Aeson..= Aeson.object
          [ "id"        Aeson..= ("ord1" :: Text)
          , "orderDate" Aeson..= ("2026-03-22T14:00:00-04:00" :: Text)
          , Aeson.Key.fromText groupsKey Aeson..=
              [ Aeson.object
                  [ "items" Aeson..=
                      [ Aeson.object
                          [ "quantity"    Aeson..= (2 :: Int)
                          , "productInfo" Aeson..= Aeson.object
                              [ "name"          Aeson..= ("Bananas" :: Text)
                              , "usItemId"      Aeson..= ("99" :: Text)
                              , "salesUnitType" Aeson..= ("EACH_WEIGHT" :: Text)
                              ]
                          , "priceInfo" Aeson..= Aeson.object
                              [ "linePrice" Aeson..= Aeson.object
                                  [ "value" Aeson..= (0.51 :: Double) ]
                              ]
                          ]
                      ]
                  ]
              ]
          ]
      ]
  ]

-- | Build a getOrder JSON with a custom salesUnitType.
mkGetOrderJsonWith :: Text -> Aeson.Value
mkGetOrderJsonWith salesType = Aeson.object
  [ "data" Aeson..= Aeson.object
      [ "order" Aeson..= Aeson.object
          [ "id"        Aeson..= ("ord1" :: Text)
          , "orderDate" Aeson..= ("2026-01-01T00:00:00Z" :: Text)
          , "groups_1" Aeson..=
              [ Aeson.object
                  [ "items" Aeson..=
                      [ Aeson.object
                          [ "quantity"    Aeson..= (1 :: Int)
                          , "productInfo" Aeson..= Aeson.object
                              [ "name"          Aeson..= ("X" :: Text)
                              , "usItemId"      Aeson..= ("1" :: Text)
                              , "salesUnitType" Aeson..= salesType
                              ]
                          ]
                      ]
                  ]
              ]
          ]
      ]
  ]

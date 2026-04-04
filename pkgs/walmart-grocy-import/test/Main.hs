{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Scientific (scientific)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (UTCTime)
import Data.Time.Format.ISO8601 (iso8601ParseM)
import Money (discrete)
import Test.QuickCheck
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck (testProperty)

import Walmart.Types
import WalmartGrocy.Reconcile (bestMatch, deduplicateBy, reconcile)
import WalmartGrocy.Types

-- Helpers

mkItem :: Text -> WalmartItem
mkItem name = WalmartItem
  { wiName          = name
  , wiQuantity      = scientific 1 0
  , wiLinePrice     = Just (discrete 597)
  , wiUsItemId      = UsItemId "123"
  , wiSalesUnitType = Each
  }

mkProduct :: Int -> Text -> (Int, Text)
mkProduct pid name = (pid, name)

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

main :: IO ()
main = defaultMain $ testGroup "walmart-grocy-import"
  [ reconcileTests
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
  ]

-- ================================================================
-- Adversarial tests
-- ================================================================

adversarialTests :: TestTree
adversarialTests = testGroup "Adversarial"
  [ testGroup "Reconcile edge cases" $
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
        case bestMatch "Boursin\174 Hot Honey" [mkProduct 1 "Boursin\174 Hot Honey"] of
          Just _  -> pure ()
          Nothing -> assertFailure "unicode match failed"

    , testCase "very long product names don't crash" $ do
        let longName = T.replicate 10000 "Great Value "
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
    ]
  ]

-- ================================================================
-- Utilities
-- ================================================================

listHead :: [a] -> a
listHead (x : _) = x
listHead []      = error "listHead: empty list in test"

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


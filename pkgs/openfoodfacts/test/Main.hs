module Main (main) where

import Data.Aeson qualified as Aeson
import Data.Maybe (isNothing)
import System.FilePath ((</>))
import Test.Tasty
import Test.Tasty.HUnit

import OpenFoodFacts

corpus :: FilePath -> FilePath
corpus name = "test" </> "corpus" </> name

decodeProduct :: FilePath -> IO (Either String (Maybe Product))
decodeProduct path = do
  body <- Aeson.eitherDecodeFileStrict' path
  pure (body >>= parseProductResponse)

main :: IO ()
main = do
  milk <- decodeProduct (corpus "milk-078742351865.json")
  beef <- decodeProduct (corpus "beef-078742269573.json")
  unknown <- decodeProduct (corpus "unknown-000000000000.json")
  defaultMain $ testGroup "openfoodfacts"
    [ testCase "a known barcode yields the label per 100 g and per serving" $
        case milk of
          Right (Just p) -> do
            offName p @?= Just "Whole Milk"
            offQuantity p @?= Just "1 gallon"
            nCalories (offPerServing p) @?= Just 150
            nProtein (offPerServing p) @?= Just 8
            nCalories (offPer100g p) @?= Just 62.5
          other -> assertFailure (show other)

    , testCase "an unknown barcode is an ordinary empty answer" $
        either assertFailure (\r -> assertBool "expected Nothing" (isNothing r)) unknown

    , testCase "a weight item reports its serving in grams with the label beside it" $
        case beef of
          Right (Just p) -> do
            offName p @?= Just "LEAN GROUND BEEF"
            offServingSize p @?= Just "1 portion (112 g)"
            (nProtein (offPerServing p), nCalories (offPerServing p), nSodium (offPerServing p))
              @?= (Just 23, Just 170, Just 0.075)
          other -> assertFailure (show other)

    , testCase "a nutrient the entry lacks is absent, never zero" $
        case Aeson.eitherDecode "{\"status\":1,\"product\":{\"code\":\"1\",\"nutriments\":{\"proteins_100g\":2}}}" >>= parseProductResponse of
          Right (Just p) -> (nProtein (offPer100g p), nFiber (offPer100g p), nProtein (offPerServing p)) @?= (Just 2, Nothing, Nothing)
          other -> assertFailure (show other)
    ]

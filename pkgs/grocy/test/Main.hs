module Main (main) where

import Data.Aeson qualified as Aeson
import Data.Time (fromGregorian)
import System.FilePath ((</>))
import Test.Tasty
import Test.Tasty.HUnit

import Grocy

corpus :: FilePath -> IO Aeson.Value
corpus name = do
  decoded <- Aeson.eitherDecodeFileStrict' ("test" </> "corpus" </> name)
  either (fail . (("corpus " <> name <> ": ") <>)) pure decoded

main :: IO ()
main = do
  stock <- corpus "stock.json"
  details <- corpus "product-details.json"
  fulfillment <- corpus "fulfillment.json"
  positions <- corpus "recipe-positions.json"
  recipes <- corpus "recipes.json"
  defaultMain $ testGroup "grocy"
    [ testCase "stock lines carry the product, the amount and the next due date" $
        case parseStockLines stock of
          Right (line : _) -> do
            productName (slProduct line) @?= "Cookies"
            slAmount line @?= 12
            slNextDue line @?= Just (fromGregorian 2027 2 19)
          other -> assertFailure (show other)

    , testCase "product details name the units, the location and the last price in cents" $
        case parseProductDetails details of
          Right d -> do
            (pdStockUnit d, pdPurchaseUnit d, pdLocation d) @?= ("Pack", "Pack", Just "Candy cupboard")
            fmap toInteger (pdLastPrice d) @?= Just 412
            pdStockAmount d @?= 12
          Left err -> assertFailure err

    , testCase "fulfillment reads Grocy's 0/1 flag as a boolean" $
        parseRecipeFulfillment fulfillment
          @?= Right RecipeFulfillment { fulfilled = False, missingProductsCount = 3, recipeCost = Just 2.9775 }

    , testCase "a recipe's positions become ingredients" $
        case parseIngredients positions of
          Right ingredients -> (length ingredients, map ingredientProduct ingredients)
                                 @?= (4, map ProductId [16, 17, 18, 10])
          Left err -> assertFailure err

    , testCase "meal-plan bookkeeping rows are not recipes" $
        case parseRecipes recipes of
          Right rs -> assertBool "only normal recipes with positive ids" (all ((> 0) . unRecipeId . recipeId) rs && not (null rs))
          Left err -> assertFailure err
    ]

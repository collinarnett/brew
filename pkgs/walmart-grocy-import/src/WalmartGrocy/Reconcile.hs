-- | Pure reconciliation logic.
module WalmartGrocy.Reconcile
  ( reconcile
  , bestMatch
  , deduplicateBy
  ) where

import Data.List (sortOn)
import Data.Ord (Down (..))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Text.Fuzzy qualified as Fuzzy

import Grocy (Product, productName)
import Walmart.Types (WalmartItem (..), WalmartOrder (..))
import WalmartGrocy.Types

reconcile :: [Product] -> WalmartOrder -> ImportPlan
reconcile products order = ImportPlan
  { ipOrderId   = woOrderId order
  , ipOrderDate = woOrderDate order
  , ipActions   = map (matchOrCreate products) (woItems order)
  }

matchOrCreate :: [Product] -> WalmartItem -> Action
matchOrCreate products item =
  case bestMatch (wiName item) products of
    Just p  -> StockExisting item p
    Nothing -> CreateAndStock item

-- | Fuzzy scores at or above this count as the same product.
matchThreshold :: Int
matchThreshold = 75

bestMatch :: Text -> [Product] -> Maybe Product
bestMatch name products =
  let candidates =
        [ (Fuzzy.score matched, p)
        | p <- products
        , Just matched <-
            [Fuzzy.match (T.toLower name) (T.toLower (productName p)) T.empty T.empty id False]
        , Fuzzy.score matched >= matchThreshold
        ]
  in case sortOn (Down . fst) candidates of
    ((_, p) : _) -> Just p
    []           -> Nothing

deduplicateBy :: Ord k => (a -> k) -> [a] -> [a]
deduplicateBy f = go Set.empty
  where
    go _ [] = []
    go seen (x : xs)
      | Set.member key seen = go seen xs
      | otherwise           = x : go (Set.insert key seen) xs
      where key = f x

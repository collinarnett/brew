-- | Pure reconciliation logic.
--
-- No IO. Takes Walmart orders and Grocy products, produces a plan
-- describing what actions to take. Trivially testable.
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

import WalmartGrocy.Types

-- | Minimum fuzzy match score (0–100) to consider a match.
matchThreshold :: Int
matchThreshold = 75

-- | Reconcile a Walmart order against existing Grocy products.
reconcile :: [GrocyProduct] -> WalmartOrder -> ImportPlan
reconcile products order = ImportPlan
  { ipOrderId   = woOrderId order
  , ipOrderDate = woOrderDate order
  , ipActions   = map (matchOrCreate products) (woItems order)
  }

-- | Match a single item to a product, or mark it for creation.
matchOrCreate :: [GrocyProduct] -> WalmartItem -> Action
matchOrCreate products item =
  case bestMatch (wiName item) products of
    Just gp -> StockExisting item gp
    Nothing      -> CreateAndStock item

-- | Find the best fuzzy match for a name among products.
-- Returns Nothing if no match meets the threshold.
bestMatch :: Text -> [GrocyProduct] -> Maybe GrocyProduct
bestMatch name products =
  let scored = [(fuzzyScore name (gpName p), p) | p <- products]
      above  = filter ((>= matchThreshold) . fst) scored
      sorted = sortOn (Down . fst) above
  in case sorted of
    ((_, p) : _) -> Just p
    []           -> Nothing

-- | Fuzzy match score between two texts.
fuzzyScore :: Text -> Text -> Int
fuzzyScore a b =
  case Fuzzy.match (T.toLower a) (T.toLower b) T.empty T.empty id False of
    Just fuzzyResult -> Fuzzy.score fuzzyResult
    Nothing          -> 0

-- | Remove duplicates from a list, keeping the first occurrence.
deduplicateBy :: Ord k => (a -> k) -> [a] -> [a]
deduplicateBy f = go Set.empty
  where
    go _ [] = []
    go seen (x : xs)
      | Set.member key seen = go seen xs
      | otherwise           = x : go (Set.insert key seen) xs
      where key = f x

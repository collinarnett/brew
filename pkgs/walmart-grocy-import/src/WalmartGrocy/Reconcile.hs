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

import Grocy.Types (GrocyProduct (..))
import Walmart.Types (WalmartItem (..), WalmartOrder (..))
import WalmartGrocy.Types

reconcile :: [GrocyProduct] -> WalmartOrder -> ImportPlan
reconcile products order = ImportPlan
  { ipOrderId   = woOrderId order
  , ipOrderDate = woOrderDate order
  , ipActions   = map (matchOrCreate products) (woItems order)
  }

matchOrCreate :: [GrocyProduct] -> WalmartItem -> Action
matchOrCreate products item =
  case bestMatch (wiName item) products of
    Just gp -> StockExisting item gp
    Nothing      -> CreateAndStock item

bestMatch :: Text -> [GrocyProduct] -> Maybe GrocyProduct
bestMatch name products =
  let threshold = 75
      scored = [(fuzzyScore name (gpName p), p) | p <- products]
      above  = filter ((>= threshold) . fst) scored
      sorted = sortOn (Down . fst) above
  in case sorted of
    ((_, p) : _) -> Just p
    []           -> Nothing

fuzzyScore :: Text -> Text -> Int
fuzzyScore a b =
  case Fuzzy.match (T.toLower a) (T.toLower b) T.empty T.empty id False of
    Just fuzzyResult -> Fuzzy.score fuzzyResult
    Nothing          -> 0

deduplicateBy :: Ord k => (a -> k) -> [a] -> [a]
deduplicateBy f = go Set.empty
  where
    go _ [] = []
    go seen (x : xs)
      | Set.member key seen = go seen xs
      | otherwise           = x : go (Set.insert key seen) xs
      where key = f x

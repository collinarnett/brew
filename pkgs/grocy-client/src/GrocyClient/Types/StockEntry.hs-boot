module GrocyClient.Types.StockEntry where
import qualified Data.Aeson
import qualified GrocyClient.Common
data StockEntry
instance Show StockEntry
instance Eq StockEntry
instance Data.Aeson.FromJSON StockEntry
instance Data.Aeson.ToJSON StockEntry

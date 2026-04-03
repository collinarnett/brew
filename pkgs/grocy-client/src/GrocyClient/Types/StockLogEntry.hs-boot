module GrocyClient.Types.StockLogEntry where
import qualified Data.Aeson
import qualified GrocyClient.Common
data StockLogEntry
instance Show StockLogEntry
instance Eq StockLogEntry
instance Data.Aeson.FromJSON StockLogEntry
instance Data.Aeson.ToJSON StockLogEntry

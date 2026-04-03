module GrocyClient.Types.StockTransactionType where
import qualified Data.Aeson
import qualified GrocyClient.Common
data StockTransactionType
instance Show StockTransactionType
instance Eq StockTransactionType
instance Data.Aeson.FromJSON StockTransactionType
instance Data.Aeson.ToJSON StockTransactionType

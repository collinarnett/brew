module GrocyClient.Types.StockLocation where
import qualified Data.Aeson
import qualified GrocyClient.Common
data StockLocation
instance Show StockLocation
instance Eq StockLocation
instance Data.Aeson.FromJSON StockLocation
instance Data.Aeson.ToJSON StockLocation

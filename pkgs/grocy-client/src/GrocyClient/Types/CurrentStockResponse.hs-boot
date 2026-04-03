module GrocyClient.Types.CurrentStockResponse where
import qualified Data.Aeson
import qualified GrocyClient.Common
data CurrentStockResponse
instance Show CurrentStockResponse
instance Eq CurrentStockResponse
instance Data.Aeson.FromJSON CurrentStockResponse
instance Data.Aeson.ToJSON CurrentStockResponse

module GrocyClient.Types.ProductPriceHistory where
import qualified Data.Aeson
import qualified GrocyClient.Common
data ProductPriceHistory
instance Show ProductPriceHistory
instance Eq ProductPriceHistory
instance Data.Aeson.FromJSON ProductPriceHistory
instance Data.Aeson.ToJSON ProductPriceHistory

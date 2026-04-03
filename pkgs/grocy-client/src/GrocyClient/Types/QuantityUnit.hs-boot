module GrocyClient.Types.QuantityUnit where
import qualified Data.Aeson
import qualified GrocyClient.Common
data QuantityUnit
instance Show QuantityUnit
instance Eq QuantityUnit
instance Data.Aeson.FromJSON QuantityUnit
instance Data.Aeson.ToJSON QuantityUnit

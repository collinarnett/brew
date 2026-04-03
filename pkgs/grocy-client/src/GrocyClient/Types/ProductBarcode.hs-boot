module GrocyClient.Types.ProductBarcode where
import qualified Data.Aeson
import qualified GrocyClient.Common
data ProductBarcode
instance Show ProductBarcode
instance Eq ProductBarcode
instance Data.Aeson.FromJSON ProductBarcode
instance Data.Aeson.ToJSON ProductBarcode

module GrocyClient.Types.Product where
import qualified Data.Aeson
import qualified GrocyClient.Common
data Product
instance Show Product
instance Eq Product
instance Data.Aeson.FromJSON Product
instance Data.Aeson.ToJSON Product

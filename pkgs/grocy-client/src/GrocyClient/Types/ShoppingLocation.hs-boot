module GrocyClient.Types.ShoppingLocation where
import qualified Data.Aeson
import qualified GrocyClient.Common
data ShoppingLocation
instance Show ShoppingLocation
instance Eq ShoppingLocation
instance Data.Aeson.FromJSON ShoppingLocation
instance Data.Aeson.ToJSON ShoppingLocation

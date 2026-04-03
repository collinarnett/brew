module GrocyClient.Types.ShoppingListItem where
import qualified Data.Aeson
import qualified GrocyClient.Common
data ShoppingListItem
instance Show ShoppingListItem
instance Eq ShoppingListItem
instance Data.Aeson.FromJSON ShoppingListItem
instance Data.Aeson.ToJSON ShoppingListItem

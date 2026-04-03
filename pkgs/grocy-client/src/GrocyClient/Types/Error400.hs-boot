module GrocyClient.Types.Error400 where
import qualified Data.Aeson
import qualified GrocyClient.Common
data Error400
instance Show Error400
instance Eq Error400
instance Data.Aeson.FromJSON Error400
instance Data.Aeson.ToJSON Error400

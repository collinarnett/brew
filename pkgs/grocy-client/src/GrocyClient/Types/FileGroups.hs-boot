module GrocyClient.Types.FileGroups where
import qualified Data.Aeson
import qualified GrocyClient.Common
data FileGroups
instance Show FileGroups
instance Eq FileGroups
instance Data.Aeson.FromJSON FileGroups
instance Data.Aeson.ToJSON FileGroups

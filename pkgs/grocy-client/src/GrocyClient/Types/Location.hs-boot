module GrocyClient.Types.Location where
import qualified Data.Aeson
import qualified GrocyClient.Common
data Location
instance Show Location
instance Eq Location
instance Data.Aeson.FromJSON Location
instance Data.Aeson.ToJSON Location

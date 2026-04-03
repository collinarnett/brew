module GrocyClient.Types.UserDto where
import qualified Data.Aeson
import qualified GrocyClient.Common
data UserDto
instance Show UserDto
instance Eq UserDto
instance Data.Aeson.FromJSON UserDto
instance Data.Aeson.ToJSON UserDto

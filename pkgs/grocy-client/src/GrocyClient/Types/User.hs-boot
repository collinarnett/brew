module GrocyClient.Types.User where
import qualified Data.Aeson
import qualified GrocyClient.Common
data User
instance Show User
instance Eq User
instance Data.Aeson.FromJSON User
instance Data.Aeson.ToJSON User

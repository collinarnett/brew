module GrocyClient.Types.UserSetting where
import qualified Data.Aeson
import qualified GrocyClient.Common
data UserSetting
instance Show UserSetting
instance Eq UserSetting
instance Data.Aeson.FromJSON UserSetting
instance Data.Aeson.ToJSON UserSetting

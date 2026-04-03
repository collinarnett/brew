module GrocyClient.Types.TimeResponse where
import qualified Data.Aeson
import qualified GrocyClient.Common
data TimeResponse
instance Show TimeResponse
instance Eq TimeResponse
instance Data.Aeson.FromJSON TimeResponse
instance Data.Aeson.ToJSON TimeResponse

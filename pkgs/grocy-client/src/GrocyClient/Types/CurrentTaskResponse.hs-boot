module GrocyClient.Types.CurrentTaskResponse where
import qualified Data.Aeson
import qualified GrocyClient.Common
data CurrentTaskResponse
instance Show CurrentTaskResponse
instance Eq CurrentTaskResponse
instance Data.Aeson.FromJSON CurrentTaskResponse
instance Data.Aeson.ToJSON CurrentTaskResponse

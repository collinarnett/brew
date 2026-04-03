module GrocyClient.Types.CurrentChoreResponse where
import qualified Data.Aeson
import qualified GrocyClient.Common
data CurrentChoreResponse
instance Show CurrentChoreResponse
instance Eq CurrentChoreResponse
instance Data.Aeson.FromJSON CurrentChoreResponse
instance Data.Aeson.ToJSON CurrentChoreResponse

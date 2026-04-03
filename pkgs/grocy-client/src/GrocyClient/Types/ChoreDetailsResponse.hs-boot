module GrocyClient.Types.ChoreDetailsResponse where
import qualified Data.Aeson
import qualified GrocyClient.Common
data ChoreDetailsResponse
instance Show ChoreDetailsResponse
instance Eq ChoreDetailsResponse
instance Data.Aeson.FromJSON ChoreDetailsResponse
instance Data.Aeson.ToJSON ChoreDetailsResponse

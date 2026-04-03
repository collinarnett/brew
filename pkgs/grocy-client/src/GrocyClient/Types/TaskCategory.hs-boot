module GrocyClient.Types.TaskCategory where
import qualified Data.Aeson
import qualified GrocyClient.Common
data TaskCategory
instance Show TaskCategory
instance Eq TaskCategory
instance Data.Aeson.FromJSON TaskCategory
instance Data.Aeson.ToJSON TaskCategory

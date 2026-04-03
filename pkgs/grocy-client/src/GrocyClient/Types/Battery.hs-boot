module GrocyClient.Types.Battery where
import qualified Data.Aeson
import qualified GrocyClient.Common
data Battery
instance Show Battery
instance Eq Battery
instance Data.Aeson.FromJSON Battery
instance Data.Aeson.ToJSON Battery

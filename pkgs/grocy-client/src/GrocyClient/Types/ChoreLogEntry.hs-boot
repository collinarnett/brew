module GrocyClient.Types.ChoreLogEntry where
import qualified Data.Aeson
import qualified GrocyClient.Common
data ChoreLogEntry
instance Show ChoreLogEntry
instance Eq ChoreLogEntry
instance Data.Aeson.FromJSON ChoreLogEntry
instance Data.Aeson.ToJSON ChoreLogEntry

module GrocyClient.Types.Chore where
import qualified Data.Aeson
import qualified GrocyClient.Common
data Chore
instance Show Chore
instance Eq Chore
instance Data.Aeson.FromJSON Chore
instance Data.Aeson.ToJSON Chore
data ChoreAssignment_type
instance Show ChoreAssignment_type
instance Eq ChoreAssignment_type
instance Data.Aeson.FromJSON ChoreAssignment_type
instance Data.Aeson.ToJSON ChoreAssignment_type
data ChorePeriod_type
instance Show ChorePeriod_type
instance Eq ChorePeriod_type
instance Data.Aeson.FromJSON ChorePeriod_type
instance Data.Aeson.ToJSON ChorePeriod_type

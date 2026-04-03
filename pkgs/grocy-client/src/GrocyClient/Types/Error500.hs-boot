module GrocyClient.Types.Error500 where
import qualified Data.Aeson
import qualified GrocyClient.Common
data Error500
instance Show Error500
instance Eq Error500
instance Data.Aeson.FromJSON Error500
instance Data.Aeson.ToJSON Error500
data Error500Error_details
instance Show Error500Error_details
instance Eq Error500Error_details
instance Data.Aeson.FromJSON Error500Error_details
instance Data.Aeson.ToJSON Error500Error_details

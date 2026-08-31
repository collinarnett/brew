-- | Configuration loading. The one setting is the User-Agent Open Food
-- Facts asks clients to send.
module NutritionMcp.Config
  ( Config (..)
  , ConfigError (..)
  , defaultConfigPath
  , loadConfig
  , renderConfigError
  ) where

import Data.Text (Text)
import Data.Text.IO qualified as T.IO
import System.Directory (XdgDirectory (XdgConfig), doesFileExist, getXdgDirectory)
import System.FilePath ((</>))
import Toml qualified
import Toml.Schema (FromValue (..), parseTableFromValue, reqKey)

import OpenFoodFacts (UserAgent (..))

newtype Config = Config
  { cfgUserAgent :: UserAgent
  }

data ConfigError
  = ConfigMissing FilePath
  | ConfigInvalid FilePath [String]
  deriving stock (Show)

renderConfigError :: ConfigError -> String
renderConfigError (ConfigMissing path) =
  "No config file at " <> path
  <> ". Create one with an [openfoodfacts] section holding user-agent."
renderConfigError (ConfigInvalid path errs) =
  "Invalid config file " <> path <> ":\n" <> unlines errs

newtype OffSection = OffSection { offUserAgent :: Text }

instance FromValue OffSection where
  fromValue = parseTableFromValue (OffSection <$> reqKey "user-agent")

newtype RawConfig = RawConfig OffSection

instance FromValue RawConfig where
  fromValue = parseTableFromValue (RawConfig <$> reqKey "openfoodfacts")

defaultConfigPath :: IO FilePath
defaultConfigPath = do
  configDir <- getXdgDirectory XdgConfig "nutrition-mcp"
  pure (configDir </> "config.toml")

loadConfig :: FilePath -> IO (Either ConfigError Config)
loadConfig path = do
  exists <- doesFileExist path
  if not exists
    then pure (Left (ConfigMissing path))
    else do
      contents <- T.IO.readFile path
      pure $ case Toml.decode contents of
        Toml.Failure errs -> Left (ConfigInvalid path errs)
        Toml.Success warnings (RawConfig section)
          | not (null warnings) -> Left (ConfigInvalid path warnings)
          | otherwise -> Right Config { cfgUserAgent = UserAgent (offUserAgent section) }

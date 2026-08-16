-- | Configuration loading.
--
-- The config file names the Grocy endpoint. The API key enters as a
-- path to a file holding the secret and is resolved here, so the rest
-- of the program only ever sees a proven 'Grocy.ApiKey'.
module GrocyMcp.Config
  ( Config (..)
  , ConfigError (..)
  , defaultConfigPath
  , loadConfig
  , renderConfigError
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as T.IO
import System.Directory (XdgDirectory (XdgConfig), doesFileExist, getXdgDirectory)
import System.FilePath ((</>))
import Toml qualified
import Toml.Schema (FromValue (..), parseTableFromValue, reqKey)

import Grocy (ApiKey (..), BaseUrl (..))

data Config = Config
  { cfgGrocyUrl    :: BaseUrl
  , cfgGrocyApiKey :: ApiKey
  }

data ConfigError
  = ConfigMissing FilePath
  | ConfigInvalid FilePath [String]
  | ApiKeyFileMissing FilePath
  deriving stock (Show)

renderConfigError :: ConfigError -> String
renderConfigError (ConfigMissing path) =
  "No config file at " <> path
  <> ". Create one with a [grocy] section holding url and api-key-file."
renderConfigError (ConfigInvalid path errs) =
  "Invalid config file " <> path <> ":\n" <> unlines errs
renderConfigError (ApiKeyFileMissing path) =
  "grocy.api-key-file points to " <> path <> ", which does not exist"

data GrocySection = GrocySection
  { grocyUrl        :: Text
  , grocyApiKeyFile :: Text
  }

instance FromValue GrocySection where
  fromValue = parseTableFromValue $
    GrocySection <$> reqKey "url" <*> reqKey "api-key-file"

newtype RawConfig = RawConfig GrocySection

instance FromValue RawConfig where
  fromValue = parseTableFromValue (RawConfig <$> reqKey "grocy")

defaultConfigPath :: IO FilePath
defaultConfigPath = do
  configDir <- getXdgDirectory XdgConfig "grocy-mcp"
  pure (configDir </> "config.toml")

loadConfig :: FilePath -> IO (Either ConfigError Config)
loadConfig path = do
  exists <- doesFileExist path
  if not exists
    then pure (Left (ConfigMissing path))
    else do
      contents <- T.IO.readFile path
      case Toml.decode contents of
        Toml.Failure errs -> pure (Left (ConfigInvalid path errs))
        -- toml-parser warns about keys the schema never consumed; in a
        -- config file an unconsumed key is a typo, so it fails the load.
        Toml.Success warnings (RawConfig grocy)
          | not (null warnings) -> pure (Left (ConfigInvalid path warnings))
          | otherwise           -> resolveApiKey grocy

resolveApiKey :: GrocySection -> IO (Either ConfigError Config)
resolveApiKey grocy = do
  let keyPath = T.unpack (grocyApiKeyFile grocy)
  keyExists <- doesFileExist keyPath
  if not keyExists
    then pure (Left (ApiKeyFileMissing keyPath))
    else do
      key <- T.strip <$> T.IO.readFile keyPath
      pure $ Right Config
        { cfgGrocyUrl    = BaseUrl (grocyUrl grocy)
        , cfgGrocyApiKey = ApiKey key
        }

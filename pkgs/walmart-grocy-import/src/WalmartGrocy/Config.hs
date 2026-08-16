{-# LANGUAGE OverloadedStrings #-}

-- | Configuration loading.
--
-- The config file names the Grocy endpoint and the Grocy objects an
-- import stocks into. The API key enters as a path to a file holding
-- the secret, never as an inline value, and is resolved here so the
-- rest of the program only ever sees a proven 'Grocy.ApiKey'.
module WalmartGrocy.Config
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
import WalmartGrocy.Types (SetupConfig (..))

data Config = Config
  { cfgGrocyUrl    :: BaseUrl
  , cfgGrocyApiKey :: ApiKey
  , cfgSetup       :: SetupConfig
  }

data ConfigError
  = ConfigMissing FilePath
  | ConfigInvalid FilePath [String]
  | ApiKeyFileMissing FilePath
  deriving stock (Show)

renderConfigError :: ConfigError -> String
renderConfigError (ConfigMissing path) =
  "No config file at " <> path
  <> ". Create one with a [grocy] section (url, api-key-file) and an"
  <> " [import] section (location, shopping-location, quantity-unit)."
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

newtype ImportSection = ImportSection SetupConfig

instance FromValue ImportSection where
  fromValue = parseTableFromValue $
    fmap ImportSection $
      SetupConfig
        <$> reqKey "location"
        <*> reqKey "shopping-location"
        <*> reqKey "quantity-unit"

data RawConfig = RawConfig
  { rawGrocy  :: GrocySection
  , rawImport :: ImportSection
  }

instance FromValue RawConfig where
  fromValue = parseTableFromValue $
    RawConfig <$> reqKey "grocy" <*> reqKey "import"

defaultConfigPath :: IO FilePath
defaultConfigPath = do
  configDir <- getXdgDirectory XdgConfig "walmart-grocy-import"
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
        Toml.Success _warnings raw -> resolveApiKey raw

resolveApiKey :: RawConfig -> IO (Either ConfigError Config)
resolveApiKey raw = do
  let keyPath = T.unpack (grocyApiKeyFile (rawGrocy raw))
  keyExists <- doesFileExist keyPath
  if not keyExists
    then pure (Left (ApiKeyFileMissing keyPath))
    else do
      key <- T.strip <$> T.IO.readFile keyPath
      let ImportSection setup = rawImport raw
      pure $ Right Config
        { cfgGrocyUrl    = BaseUrl (grocyUrl (rawGrocy raw))
        , cfgGrocyApiKey = ApiKey key
        , cfgSetup       = setup
        }

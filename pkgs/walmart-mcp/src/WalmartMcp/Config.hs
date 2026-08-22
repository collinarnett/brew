-- | Configuration loading.
--
-- The config file supplies the persisted query hashes for operations
-- that never appear in Walmart's frontend bundles, and so cannot be
-- discovered. Everything else the client needs it finds for itself.
module WalmartMcp.Config
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
import Toml.Schema (FromValue (..), optKey, parseTableFromValue, reqKey)

import Walmart (Catalog, OperationName (..), mkQueryHash, seededCatalog)

data Config = Config
  { cfgCatalogPath :: Maybe FilePath
  , cfgSeeds       :: Catalog
  }

data ConfigError
  = ConfigMissing FilePath
  | ConfigInvalid FilePath [String]
  | HashMalformed FilePath Text Text
  deriving stock (Show)

renderConfigError :: ConfigError -> String
renderConfigError (ConfigMissing path) =
  "No config file at " <> path
  <> ". Create one with an [[operation]] entry per hash that discovery cannot find."
renderConfigError (ConfigInvalid path errs) =
  "Invalid config file " <> path <> ":\n" <> unlines errs
renderConfigError (HashMalformed path name raw) =
  "In " <> path <> ", operation " <> T.unpack name
  <> " has hash " <> show raw
  <> ", which is not 64 lowercase hex characters."

data OperationEntry = OperationEntry
  { entryOperation :: Text
  , entryRawHash   :: Text
  }

instance FromValue OperationEntry where
  fromValue = parseTableFromValue $
    OperationEntry <$> reqKey "name" <*> reqKey "hash"

data RawConfig = RawConfig
  { rawCatalogFile :: Maybe Text
  , rawOperations  :: [OperationEntry]
  }

instance FromValue RawConfig where
  fromValue = parseTableFromValue $
    RawConfig <$> optKey "catalog-file" <*> reqKey "operation"

defaultConfigPath :: IO FilePath
defaultConfigPath = do
  configDir <- getXdgDirectory XdgConfig "walmart-mcp"
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
        -- toml-parser warns about keys the schema never consumed; in a
        -- config file an unconsumed key is a typo, so it fails the load.
        Toml.Success warnings raw
          | not (null warnings) -> Left (ConfigInvalid path warnings)
          | otherwise           -> toConfig path raw

toConfig :: FilePath -> RawConfig -> Either ConfigError Config
toConfig path raw = do
  seeds <- traverse toSeed (rawOperations raw)
  pure Config
    { cfgCatalogPath = T.unpack <$> rawCatalogFile raw
    , cfgSeeds       = seededCatalog seeds
    }
  where
    toSeed entry = case mkQueryHash (entryRawHash entry) of
      Nothing -> Left (HashMalformed path (entryOperation entry) (entryRawHash entry))
      Just hash -> Right (OperationName (entryOperation entry), hash)

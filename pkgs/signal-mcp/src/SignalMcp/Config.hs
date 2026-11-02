-- | Configuration. One file serves all three modes; the read server uses
-- only the database, so it starts without a daemon to talk to. Nothing is
-- read from the environment: an MCP client may start the servers with
-- almost none of it.
module SignalMcp.Config
  ( Config (..)
  , DaemonSettings (..)
  , ConfigError (..)
  , defaultConfigPath
  , loadConfig
  , renderConfigError
  , parseConfig
  , RawConfig (..)
  ) where

import Data.Bifunctor (first)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as T.IO
import System.Directory (XdgDirectory (XdgConfig), doesFileExist, getXdgDirectory)
import System.FilePath (isAbsolute, (</>))
import Toml qualified
import Toml.Schema (FromValue (..), optKey, parseTableFromValue, reqKey)

import SignalMcp.Daemon (Account, parseAccount)

data Config = Config
  { cfgDatabase :: FilePath
  , cfgDaemon :: DaemonSettings
  }
  deriving stock (Eq, Show)

-- | What the ingester and the send server need to reach signal-cli.
data DaemonSettings = DaemonSettings
  { daemonSocket :: FilePath
  , daemonAccount :: Maybe Account
  }
  deriving stock (Eq, Show)

data ConfigError
  = ConfigMissing FilePath
  | ConfigInvalid FilePath [String]
  | ConfigFieldUnusable Text Text
  deriving stock (Eq, Show)

renderConfigError :: ConfigError -> String
renderConfigError = \case
  ConfigMissing path ->
    "No config file at " <> path <> ". Create one with a [signal] section holding database and socket."
  ConfigInvalid path errs -> "Invalid config file " <> path <> ":\n" <> unlines errs
  ConfigFieldUnusable field reason -> "signal." <> T.unpack field <> ": " <> T.unpack reason

data RawConfig = RawConfig
  { rawDatabase :: FilePath
  , rawSocket :: FilePath
  , rawAccount :: Maybe Text
  }
  deriving stock (Eq, Show)

newtype RawDocument = RawDocument RawConfig

instance FromValue RawConfig where
  fromValue =
    parseTableFromValue $
      RawConfig <$> reqKey "database" <*> reqKey "socket" <*> optKey "account"

instance FromValue RawDocument where
  fromValue = parseTableFromValue (RawDocument <$> reqKey "signal")

defaultConfigPath :: IO FilePath
defaultConfigPath = (</> "config.toml") <$> getXdgDirectory XdgConfig "signal-mcp"

parseConfig :: Text -> Either [String] RawConfig
parseConfig contents = case Toml.decode contents of
  Toml.Failure errs -> Left errs
  Toml.Success warnings (RawDocument raw)
    | not (null warnings) -> Left warnings
    | otherwise -> Right raw

loadConfig :: FilePath -> IO (Either ConfigError Config)
loadConfig path = do
  exists <- doesFileExist path
  if not exists
    then pure (Left (ConfigMissing path))
    else do
      contents <- T.IO.readFile path
      pure (first (ConfigInvalid path) (parseConfig contents) >>= resolve)

resolve :: RawConfig -> Either ConfigError Config
resolve raw = do
  database <- absolute "database" (rawDatabase raw)
  socket <- absolute "socket" (rawSocket raw)
  account <- traverse (first (ConfigFieldUnusable "account") . parseAccount) (rawAccount raw)
  pure (Config database (DaemonSettings socket account))
  where
    absolute field path
      | isAbsolute path = Right path
      | otherwise = Left (ConfigFieldUnusable field "must be an absolute path")


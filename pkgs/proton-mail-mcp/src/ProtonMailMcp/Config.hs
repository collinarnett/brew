-- | Configuration loading. The password and the pinned certificate enter
-- as paths and are resolved here, once, so the server never starts with
-- settings it cannot use.
module ProtonMailMcp.Config
  ( Config (..)
  , BridgeEndpoint (..)
  , ConfigError (..)
  , defaultConfigPath
  , loadConfig
  , renderConfigError
  , parseConfig
  , RawConfig (..)
  ) where

import Control.Exception (IOException, try)
import Data.Bifunctor (first)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as T.IO
import Data.X509 (SignedCertificate)
import Data.X509.File (readSignedObject)
import Data.MIME (Mailbox)
import Network.Socket (PortNumber)
import System.Directory (XdgDirectory (XdgConfig), doesFileExist, getXdgDirectory)
import System.FilePath ((</>))
import Toml qualified
import Toml.Schema (FromValue (..), optKey, parseTableFromValue, reqKey)

import ProtonMailMcp.Message (parseSender)

data BridgeEndpoint = BridgeEndpoint
  { endpointHost :: String
  , endpointImapPort :: PortNumber
  }
  deriving stock (Eq, Show)

data Config = Config
  { cfgEndpoint :: BridgeEndpoint
  , cfgUsername :: Text
  , cfgPassword :: Text
  , cfgPinnedCertificate :: SignedCertificate
  , cfgDraftSender :: Mailbox
  }

data ConfigError
  = ConfigMissing FilePath
  | ConfigInvalid FilePath [String]
  | ConfigFieldUnusable Text Text
  deriving stock (Show)

renderConfigError :: ConfigError -> String
renderConfigError (ConfigMissing path) =
  "No config file at " <> path
    <> ". Create one with a [bridge] section holding username, password-file,\
       \ certificate-file and draft-from."
renderConfigError (ConfigInvalid path errs) =
  "Invalid config file " <> path <> ":\n" <> unlines errs
renderConfigError (ConfigFieldUnusable field reason) =
  "bridge." <> T.unpack field <> ": " <> T.unpack reason

data RawConfig = RawConfig
  { rawHost :: Maybe String
  , rawImapPort :: Maybe Integer
  , rawUsername :: Text
  , rawPasswordFile :: FilePath
  , rawCertificateFile :: FilePath
  , rawDraftFrom :: Text
  }
  deriving stock (Eq, Show)

newtype RawDocument = RawDocument RawConfig

instance FromValue RawConfig where
  fromValue =
    parseTableFromValue $
      RawConfig
        <$> optKey "host"
        <*> optKey "imap-port"
        <*> reqKey "username"
        <*> reqKey "password-file"
        <*> reqKey "certificate-file"
        <*> reqKey "draft-from"

instance FromValue RawDocument where
  fromValue = parseTableFromValue (RawDocument <$> reqKey "bridge")

defaultConfigPath :: IO FilePath
defaultConfigPath = do
  configDir <- getXdgDirectory XdgConfig "proton-mail-mcp"
  pure (configDir </> "config.toml")

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
      case first (ConfigInvalid path) (parseConfig contents) of
        Left err -> pure (Left err)
        Right raw -> resolve raw

resolve :: RawConfig -> IO (Either ConfigError Config)
resolve raw = do
  password <- readPassword (rawPasswordFile raw)
  certificate <- readCertificate (rawCertificateFile raw)
  pure $ do
    port <- imapPort (rawImapPort raw)
    sender <- first (ConfigFieldUnusable "draft-from") (parseSender (rawDraftFrom raw))
    Config
      (BridgeEndpoint (fromMaybe "127.0.0.1" (rawHost raw)) port)
      (rawUsername raw)
      <$> password
      <*> certificate
      <*> pure sender

imapPort :: Maybe Integer -> Either ConfigError PortNumber
imapPort Nothing = Right 1143
imapPort (Just port)
  | port < 1 || port > 65535 = Left (ConfigFieldUnusable "imap-port" "must be between 1 and 65535")
  | otherwise = Right (fromInteger port)

readPassword :: FilePath -> IO (Either ConfigError Text)
readPassword path = do
  contents <- try @IOException (T.IO.readFile path)
  pure $ case T.strip <$> contents of
    Left err -> Left (ConfigFieldUnusable "password-file" (T.pack (show err)))
    Right password
      | T.null password -> Left (ConfigFieldUnusable "password-file" (T.pack path <> " is empty"))
      | otherwise -> Right password

readCertificate :: FilePath -> IO (Either ConfigError SignedCertificate)
readCertificate path = do
  certificates <- try @IOException (readSignedObject path)
  pure $ case certificates of
    Left err -> Left (ConfigFieldUnusable "certificate-file" (T.pack (show err)))
    Right (certificate : _) -> Right certificate
    Right [] -> Left (ConfigFieldUnusable "certificate-file" (T.pack path <> " holds no certificate"))

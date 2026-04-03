{-# LANGUAGE OverloadedStrings #-}

-- | Firefox cookie extraction via SQLite.
module BrowserCookies
  ( getFirefoxCookies
  , CookieConfig (..)
  , defaultConfig
  , CookieError (..)
  ) where

import Control.Monad (when)
import Data.ByteString.Char8 qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as T.IO
import Data.Time.Clock (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Database.SQLite.Simple
import Network.HTTP.Client (Cookie (..), CookieJar, createCookieJar)
import System.Directory (copyFile, getHomeDirectory, removeFile)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)

data CookieConfig = CookieConfig
  { ccVerbose :: Bool
  } deriving stock (Show, Eq)

defaultConfig :: CookieConfig
defaultConfig = CookieConfig { ccVerbose = False }

data CookieError
  = NoCookiesFound Text FilePath
  | NoDefaultProfile FilePath
  deriving stock (Show, Eq)

data CookieRow = CookieRow
  { crName   :: String
  , crValue  :: String
  , crHost   :: String
  , crPath   :: String
  , crSecure :: Int
  , crExpiry :: Int
  }

instance FromRow CookieRow where
  fromRow = CookieRow <$> field <*> field <*> field <*> field <*> field <*> field

-- | Read cookies for a domain from Firefox's SQLite cookie database.
getFirefoxCookies :: CookieConfig -> Text -> IO (Either CookieError CookieJar)
getFirefoxCookies cfg domain = do
  let verbose = ccVerbose cfg
  result <- findCookieDb
  case result of
    Left err -> pure (Left err)
    Right dbPath -> do
      when verbose $
        hPutStrLn stderr ("Reading cookies from: " <> dbPath)
      let tmpPath = dbPath <> ".wgi-copy"
      copyFile dbPath tmpPath
      conn <- open tmpPath
      rows <- query conn
        "SELECT name, value, host, path, isSecure, expiry \
        \FROM moz_cookies WHERE host LIKE ?"
        (Only ("%" <> T.unpack domain))
        :: IO [CookieRow]
      close conn
      removeFile tmpPath
      when verbose $
        hPutStrLn stderr ("Loaded " <> show (length rows) <> " cookies for " <> T.unpack domain)
      if null rows
        then pure (Left (NoCookiesFound domain dbPath))
        else pure (Right (createCookieJar (map toCookie rows)))

toCookie :: CookieRow -> Cookie
toCookie row = Cookie
  { cookie_name             = BS.pack (crName row)
  , cookie_value            = BS.pack (crValue row)
  , cookie_domain           = BS.pack (crHost row)
  , cookie_path             = BS.pack (crPath row)
  , cookie_secure_only      = crSecure row /= 0
  , cookie_http_only        = False
  , cookie_host_only        = False
  , cookie_expiry_time      = epochToUTC (crExpiry row)
  , cookie_creation_time    = epochToUTC 0
  , cookie_last_access_time = epochToUTC 0
  , cookie_persistent       = True
  }

epochToUTC :: Int -> UTCTime
epochToUTC = posixSecondsToUTCTime . fromIntegral

findCookieDb :: IO (Either CookieError FilePath)
findCookieDb = do
  home <- getHomeDirectory
  let ffDir = home </> ".mozilla" </> "firefox"
      iniPath = ffDir </> "profiles.ini"
  contents <- T.IO.readFile iniPath
  let profilePath = parseDefaultProfile (T.lines contents)
  case profilePath of
    Just relPath -> pure (Right (ffDir </> relPath </> "cookies.sqlite"))
    Nothing -> pure (Left (NoDefaultProfile iniPath))

parseDefaultProfile :: [Text] -> Maybe FilePath
parseDefaultProfile = go Nothing False
  where
    go currentPath isDefault [] =
      if isDefault then currentPath else Nothing
    go currentPath isDefault (line : rest)
      | T.isPrefixOf "[Profile" line =
          if isDefault then currentPath
          else go Nothing False rest
      | T.isPrefixOf "Path=" line =
          go (Just (T.unpack (T.drop 5 line))) isDefault rest
      | T.isInfixOf "Default=1" line =
          go currentPath True rest
      | otherwise =
          go currentPath isDefault rest

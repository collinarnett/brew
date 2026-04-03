{-# LANGUAGE OverloadedStrings #-}

-- | Firefox cookie extraction via SQLite.
module WalmartGrocy.Cookies
  ( getFirefoxCookies
  ) where

import Data.ByteString.Char8 qualified as BS
import Data.List (isPrefixOf, isInfixOf)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Database.SQLite.Simple
import Network.HTTP.Client (Cookie (..), CookieJar, createCookieJar)
import System.Directory (copyFile, getHomeDirectory, removeFile)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)

-- | Read cookies for a domain from Firefox's SQLite cookie database.
getFirefoxCookies :: Text -> IO CookieJar
getFirefoxCookies domain = do
  dbPath <- findCookieDb
  hPutStrLn stderr ("Reading cookies from: " <> dbPath)
  -- Copy to temp to avoid locking conflicts with running Firefox.
  -- Firefox holds a WAL lock on the original file.
  let tmpPath = dbPath <> ".wgi-copy"
  copyFile dbPath tmpPath
  conn <- open tmpPath
  rows <- query conn
    "SELECT name, value, host, path, isSecure, expiry \
    \FROM moz_cookies WHERE host LIKE ?"
    (Only ("%" <> T.unpack domain))
  close conn
  removeFile tmpPath
  hPutStrLn stderr ("Loaded " <> show (length rows) <> " cookies for " <> T.unpack domain)
  if null rows
    then fail ("No cookies found for " <> T.unpack domain
      <> " in " <> dbPath
      <> ". Log into walmart.com in Firefox first.")
    else pure (createCookieJar (map toCookie rows))

toCookie :: (String, String, String, String, Int, Int) -> Cookie
toCookie (name, value, host, path, secure, expiry) = Cookie
  { cookie_name             = BS.pack name
  , cookie_value            = BS.pack value
  , cookie_domain           = BS.pack host
  , cookie_path             = BS.pack path
  , cookie_secure_only      = secure /= 0
  , cookie_http_only        = False
  , cookie_host_only        = False
  , cookie_expiry_time      = epochToUTC expiry
  , cookie_creation_time    = epochToUTC 0
  , cookie_last_access_time = epochToUTC 0
  , cookie_persistent       = True
  }

epochToUTC :: Int -> UTCTime
epochToUTC = posixSecondsToUTCTime . fromIntegral

-- | Find the default Firefox profile's cookies.sqlite by parsing profiles.ini.
findCookieDb :: IO FilePath
findCookieDb = do
  home <- getHomeDirectory
  let ffDir = home </> ".mozilla" </> "firefox"
      iniPath = ffDir </> "profiles.ini"
  contents <- readFile iniPath
  let profilePath = parseDefaultProfile (lines contents)
  case profilePath of
    Just relPath -> do
      let fullPath = ffDir </> relPath </> "cookies.sqlite"
      hPutStrLn stderr ("Default Firefox profile: " <> relPath)
      pure fullPath
    Nothing -> fail ("Could not find default profile in " <> iniPath)

-- | Parse profiles.ini to find the Path of the profile with Default=1.
parseDefaultProfile :: [String] -> Maybe FilePath
parseDefaultProfile = go Nothing False
  where
    go currentPath isDefault [] =
      if isDefault then currentPath else Nothing
    go currentPath isDefault (line : rest)
      | "[Profile" `isPrefixOf` line =
          -- Start of a new section. If previous section was default, return it.
          if isDefault then currentPath
          else go Nothing False rest
      | "Path=" `isPrefixOf` line =
          go (Just (drop 5 line)) isDefault rest
      | "Default=1" `isInfixOf` line =
          go currentPath True rest
      | otherwise =
          go currentPath isDefault rest

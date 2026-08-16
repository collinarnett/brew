{-# LANGUAGE OverloadedStrings #-}

-- | Firefox cookie extraction via SQLite.
module BrowserCookies
  ( getFirefoxCookies
  , CookieError (..)
  ) where

import Control.Exception (finally)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as T.IO
import Data.Time.Clock (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Database.SQLite.Simple
import Network.HTTP.Client (Cookie (..), CookieJar, createCookieJar)
import System.Directory (copyFile, doesFileExist, getHomeDirectory, removeFile)
import System.FilePath ((</>))

data CookieError
  = NoProfilesIni FilePath
  | NoDefaultProfile FilePath
  | NoCookiesFound Text FilePath
  deriving stock (Show, Eq)

data CookieRow = CookieRow
  { crName         :: Text
  , crValue        :: Text
  , crHost         :: Text
  , crPath         :: Text
  , crSecure       :: Bool
  , crHttpOnly     :: Bool
  , crExpiry       :: Int  -- seconds since epoch
  , crCreated      :: Int  -- microseconds since epoch
  , crLastAccessed :: Int  -- microseconds since epoch
  }

instance FromRow CookieRow where
  fromRow = CookieRow
    <$> field <*> field <*> field <*> field
    <*> field <*> field <*> field <*> field <*> field

-- | Read cookies for a domain from the default Firefox profile's SQLite
-- cookie database.
getFirefoxCookies :: Text -> IO (Either CookieError CookieJar)
getFirefoxCookies domain = do
  found <- findCookieDb
  case found of
    Left err -> pure (Left err)
    Right dbPath -> do
      -- Firefox holds a WAL lock on the live database while running,
      -- so query a throwaway copy.
      let copyPath = dbPath <> ".browser-cookies-copy"
      copyFile dbPath copyPath
      rows <- queryCookies copyPath domain `finally` removeFile copyPath
      pure $ if null rows
        then Left (NoCookiesFound domain dbPath)
        else Right (createCookieJar (map toCookie rows))

queryCookies :: FilePath -> Text -> IO [CookieRow]
queryCookies dbPath domain =
  withConnection dbPath $ \conn ->
    query conn
      "SELECT name, value, host, path, isSecure, isHttpOnly, \
      \expiry, creationTime, lastAccessed \
      \FROM moz_cookies WHERE host LIKE ?"
      (Only ("%" <> T.unpack domain))

toCookie :: CookieRow -> Cookie
toCookie row = Cookie
  { cookie_name             = TE.encodeUtf8 (crName row)
  , cookie_value            = TE.encodeUtf8 (crValue row)
  , cookie_domain           = TE.encodeUtf8 (crHost row)
  , cookie_path             = TE.encodeUtf8 (crPath row)
  , cookie_secure_only      = crSecure row
  , cookie_http_only        = crHttpOnly row
  -- Firefox stores domain cookies with a leading dot on the host;
  -- a bare host means the cookie is for that exact host only.
  , cookie_host_only        = not ("." `T.isPrefixOf` crHost row)
  , cookie_expiry_time      = epochSecondsToUTC (crExpiry row)
  , cookie_creation_time    = epochMicrosToUTC (crCreated row)
  , cookie_last_access_time = epochMicrosToUTC (crLastAccessed row)
  , cookie_persistent       = True
  }

epochSecondsToUTC :: Int -> UTCTime
epochSecondsToUTC = posixSecondsToUTCTime . fromIntegral

epochMicrosToUTC :: Int -> UTCTime
epochMicrosToUTC micros = posixSecondsToUTCTime (fromIntegral micros / 1e6)

findCookieDb :: IO (Either CookieError FilePath)
findCookieDb = do
  home <- getHomeDirectory
  let ffDir = home </> ".mozilla" </> "firefox"
      iniPath = ffDir </> "profiles.ini"
  iniExists <- doesFileExist iniPath
  if not iniExists
    then pure (Left (NoProfilesIni iniPath))
    else do
      contents <- T.IO.readFile iniPath
      pure $ case parseDefaultProfile (T.lines contents) of
        Just relPath -> Right (ffDir </> relPath </> "cookies.sqlite")
        Nothing      -> Left (NoDefaultProfile iniPath)

-- | Find the profile section marked Default=1. Any section header ends
-- the current section, so an [Install] section's Default=<path> line can
-- never be mistaken for a profile's Default=1 flag.
parseDefaultProfile :: [Text] -> Maybe FilePath
parseDefaultProfile = go Nothing False
  where
    go currentPath isDefault [] =
      if isDefault then currentPath else Nothing
    go currentPath isDefault (line : rest)
      | T.isPrefixOf "[" line =
          if isDefault then currentPath
          else go Nothing False rest
      | T.isPrefixOf "Path=" line =
          go (Just (T.unpack (T.drop 5 line))) isDefault rest
      | T.strip line == "Default=1" =
          go currentPath True rest
      | otherwise =
          go currentPath isDefault rest

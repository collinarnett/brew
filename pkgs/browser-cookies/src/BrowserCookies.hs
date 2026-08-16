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
  { crName   :: Text
  , crValue  :: Text
  , crHost   :: Text
  , crPath   :: Text
  , crSecure :: Int
  , crExpiry :: Int
  }

instance FromRow CookieRow where
  fromRow = CookieRow <$> field <*> field <*> field <*> field <*> field <*> field

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
      "SELECT name, value, host, path, isSecure, expiry \
      \FROM moz_cookies WHERE host LIKE ?"
      (Only ("%" <> T.unpack domain))

toCookie :: CookieRow -> Cookie
toCookie row = Cookie
  { cookie_name             = TE.encodeUtf8 (crName row)
  , cookie_value            = TE.encodeUtf8 (crValue row)
  , cookie_domain           = TE.encodeUtf8 (crHost row)
  , cookie_path             = TE.encodeUtf8 (crPath row)
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
  iniExists <- doesFileExist iniPath
  if not iniExists
    then pure (Left (NoProfilesIni iniPath))
    else do
      contents <- T.IO.readFile iniPath
      pure $ case parseDefaultProfile (T.lines contents) of
        Just relPath -> Right (ffDir </> relPath </> "cookies.sqlite")
        Nothing      -> Left (NoDefaultProfile iniPath)

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

{-# LANGUAGE OverloadedStrings #-}

-- | Maintenance CLI for the persisted query catalog.
--
-- Refreshing reads Walmart's current frontend build and folds what it
-- finds over the catalog on disk. The MCP server does the same thing on
-- its own when a hash is retired; this exists for running it on purpose
-- and for seeing what is known.
module Main (main) where

import Data.Aeson qualified as Aeson
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.ByteString.Lazy.Char8 qualified as LBS
import Data.Text qualified as T
import Data.Text.IO qualified as T.IO
import Network.HTTP.Client (newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import System.Environment (getArgs)
import System.Exit (die)

import BrowserCookies (getFirefoxCookies)
import System.IO (stderr)
import Walmart (probe)
import Walmart qualified

import Walmart.Catalog
  ( BuildId (..)
  , Catalog
  , CatalogEntry (..)
  , Origin (..)
  , adoptDiscovered
  , catalogEntries
  , catalogSize
  , defaultCatalogPath
  , loadCatalog
  , renderCatalogError
  , saveCatalog
  )
import Walmart.Discovery (discover, renderDiscoveryError)
import Walmart.Types (OperationName (..), unQueryHash)

usage :: String
usage = unlines
  [ "Usage: walmart-extractor <command> [catalog-file]"
  , ""
  , "  refresh  Scan Walmart's current frontend build and update the catalog"
  , "  show     List the operations the catalog holds"
  , "  probe <operation> <gateway> <query|mutation> <variables.json> [path-suffix]"
  , "           Send one catalogued operation with the variables in the file,"
  , "           using the Firefox Walmart session, and print the response."
  , "           Gateways: " <> T.unpack (T.intercalate ", " (map Walmart.servicePath Walmart.allServices))
  , ""
  , "The catalog defaults to $XDG_STATE_HOME/walmart/catalog.json."
  ]

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["refresh"]       -> defaultCatalogPath >>= refresh
    ["refresh", path] -> refresh path
    ["show"]          -> defaultCatalogPath >>= list
    ["show", path]    -> list path
    ["probe", op, gateway, kind, file] -> runProbe op gateway kind file ""
    ["probe", op, gateway, kind, file, suffix] -> runProbe op gateway kind file suffix
    _                 -> die usage

refresh :: FilePath -> IO ()
refresh path = do
  known <- readCatalog path
  mgr <- newManager tlsManagerSettings
  found <- discover mgr
  case found of
    Left err -> die (T.unpack (renderDiscoveryError err))
    Right discovered -> do
      let merged = adoptDiscovered discovered known
      saveCatalog path merged
      putStrLn $
        show (catalogSize discovered) <> " operations discovered, "
        <> show (catalogSize merged) <> " now known, written to " <> path

list :: FilePath -> IO ()
list path = do
  catalog <- readCatalog path
  if catalogSize catalog == 0
    then putStrLn ("No operations in " <> path <> ". Run: walmart-extractor refresh")
    else mapM_ (T.IO.putStrLn . renderEntry) (catalogEntries catalog)

renderEntry :: CatalogEntry -> T.Text
renderEntry entry =
  T.justifyLeft 34 ' ' (unOperationName (entryName entry))
  <> unQueryHash (entryHash entry)
  <> "  " <> renderOrigin (entryOrigin entry)

renderOrigin :: Origin -> T.Text
renderOrigin Seeded = "configured"
renderOrigin (Discovered build at) =
  unBuildId build <> " at " <> T.pack (show at)

readCatalog :: FilePath -> IO Catalog
readCatalog path = do
  loaded <- loadCatalog path
  case loaded of
    Left err  -> die (T.unpack (renderCatalogError err))
    Right cat -> pure cat

runProbe :: String -> String -> String -> FilePath -> String -> IO ()
runProbe op gateway kind file suffix = do
  service <- maybe (die ("unknown gateway: " <> gateway)) pure (Walmart.parseService (T.pack gateway))
  opKind  <- maybe (die ("kind must be query or mutation, not " <> kind)) pure (Walmart.parseKind (T.pack kind))
  variables <- either (\e -> die ("variables file: " <> e)) pure =<< Aeson.eitherDecodeFileStrict' file
  cookies <- either (die . show) pure =<< getFirefoxCookies ".walmart.com"
  catalogPath <- Walmart.defaultCatalogPath
  env <- either (die . show) pure =<< Walmart.newEnv cookies catalogPath (Walmart.seededCatalog [])
  let target = Walmart.Target
        { Walmart.targetName    = OperationName (T.pack op)
        , Walmart.targetService = service
        , Walmart.targetKind    = opKind
        , Walmart.targetSuffix  = T.pack suffix
        }
  result <- probe env target variables
  notices <- Walmart.takeNotices env
  mapM_ (T.IO.hPutStrLn stderr) notices
  case result of
    Left err -> die (show err)
    Right val -> LBS.putStrLn (encodePretty val)

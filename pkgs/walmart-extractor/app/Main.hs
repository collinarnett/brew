{-# LANGUAGE OverloadedStrings #-}

-- | Maintenance CLI for the persisted query catalog.
--
-- Refreshing reads Walmart's current frontend build and folds what it
-- finds over the catalog on disk. The MCP server does the same thing on
-- its own when a hash is retired; this exists for running it on purpose
-- and for seeing what is known.
module Main (main) where

import Data.Text qualified as T
import Data.Text.IO qualified as T.IO
import Network.HTTP.Client (newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import System.Environment (getArgs)
import System.Exit (die)

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

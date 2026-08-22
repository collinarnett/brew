-- | Walmart GraphQL API client.
--
-- The persisted query hashes Walmart's gateways require are not part of
-- this library. They are discovered from Walmart's own frontend build
-- and kept in a catalog file, which 'newEnv' loads and the API
-- refreshes on its own when a hash is retired.
--
-- @
-- import qualified Walmart
-- import BrowserCookies (getFirefoxCookies)
--
-- main :: IO ()
-- main = do
--   Right cookies <- getFirefoxCookies ".walmart.com"
--   catalogPath <- Walmart.defaultCatalogPath
--   Right env <- Walmart.newEnv cookies catalogPath
--   Right orders <- Walmart.getOrders env Nothing 10
--   print orders
-- @
module Walmart
  ( -- * Environment
    Env
  , newEnv
  , takeNotices
    -- * API
  , getOrders
  , getOrderDetails
  , searchProducts
    -- * Endpoint catalog
  , refreshCatalog
  , effectiveCatalog
  , defaultCatalogPath
  , Catalog
  , seededCatalog
  , catalogEntries
  , CatalogEntry (..)
  , Origin (..)
  , BuildId (..)
    -- * Types
  , module Walmart.Types
  ) where

import Walmart.Catalog
  ( BuildId (..)
  , Catalog
  , CatalogEntry (..)
  , Origin (..)
  , catalogEntries
  , defaultCatalogPath
  , seededCatalog
  )
import Walmart.Env
import Walmart.Types

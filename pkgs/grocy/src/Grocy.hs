-- | Grocy REST API client.
--
-- @
-- import qualified Grocy
--
-- main :: IO ()
-- main = do
--   env <- Grocy.newEnv "https://grocy.example.com" "your-api-key"
--   Right products <- Grocy.getProducts env
--   print products
-- @
module Grocy
  ( -- * Environment
    Env
  , newEnv
    -- * API
  , getProducts
  , createProduct
  , addStock
  , ensureSetup
    -- * Types
  , ProductId (..)
  , GrocyProduct (..)
  , GrocyError (..)
  , GrocySetup (..)
  , SetupConfig (..)
  ) where

import Grocy.Env
import Grocy.Types

-- | Walmart GraphQL API client.
--
-- @
-- import qualified Walmart
-- import BrowserCookies (getFirefoxCookies)
--
-- main :: IO ()
-- main = do
--   Right cookies <- getFirefoxCookies ".walmart.com"
--   env <- Walmart.newEnv cookies
--   Right orders <- Walmart.getOrders env Nothing 10
--   print orders
-- @
module Walmart
  ( -- * Environment
    Env
  , newEnv
    -- * API
  , getOrders
  , getOrder
    -- * Types
  , module Walmart.Types
  ) where

import Walmart.Env
import Walmart.Types

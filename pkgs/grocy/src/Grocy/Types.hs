{-# LANGUAGE OverloadedStrings #-}

module Grocy.Types
  ( -- * Environment
    Env (..)
  , ProductId (..)
  , GrocyProduct (..)
  , GrocyError (..)
  , GrocySetup (..)
  , SetupConfig (..)
  ) where

import Data.Text (Text)
import Network.HTTP.Client (Manager)

data Env = Env
  { envBaseUrl :: Text
  , envApiKey  :: Text
  , envManager :: Manager
  }

newtype ProductId = ProductId { unProductId :: Int }
  deriving stock (Show, Eq, Ord)

data GrocyProduct = GrocyProduct
  { gpId   :: ProductId
  , gpName :: Text
  } deriving stock (Show, Eq)

data GrocyError
  = GrocyDecodeError String
  | GrocyParseError String
  | GrocyProductNotFound Text
  | GrocyEntityNotFound Text Text
  | GrocyCreateError Text String
  | GrocyMissingId Text
  | GrocyHttpError Text Int
  | GrocyIdParseError String
  deriving stock (Show, Eq)

data GrocySetup = GrocySetup
  { gsLocationId        :: Int
  , gsShoppingLocationId :: Int
  , gsPieceUnitId       :: Int
  } deriving stock (Show)

data SetupConfig = SetupConfig
  { scLocationName         :: Text
  , scShoppingLocationName :: Text
  , scQuantityUnitName     :: Text
  } deriving stock (Show)

{-# LANGUAGE OverloadedStrings #-}

module Grocy.Internal.JSON
  ( parseGrocyProducts
  ) where

import Data.Aeson
import Data.Aeson.Types (Parser, parseEither)
import Data.Vector qualified as V

import Grocy.Types

parseGrocyProducts :: Value -> Either String [GrocyProduct]
parseGrocyProducts = parseEither $ withArray "products" $ \arr ->
  traverse parseGrocyProduct (V.toList arr)

parseGrocyProduct :: Value -> Parser GrocyProduct
parseGrocyProduct = withObject "product" $ \obj -> do
  pid  <- ProductId <$> obj .: "id"
  name <- obj .: "name"
  pure GrocyProduct { gpId = pid, gpName = name }

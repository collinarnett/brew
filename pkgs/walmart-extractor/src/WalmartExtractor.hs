{-# LANGUAGE OverloadedStrings #-}

-- | Walmart endpoint hash discovery.
--
-- Discovers GraphQL persisted query hashes by scraping Walmart's JS bundles.
-- This is a developer tool — its output is committed as generated Haskell
-- source into the walmart library package.
module WalmartExtractor
  ( discoverEndpoints
  , Endpoints (..)
    -- * Parsers (exported for testing)
  , parseScriptUrls
  , parseHashPair
  , collectAll
  ) where

import Data.Attoparsec.Text qualified as A
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.HTTP.Client (Manager, httpLbs, parseRequest, responseBody)
import System.Process (readProcess)

walmartBase :: Text
walmartBase = "https://www.walmart.com"

-- | Known GraphQL operations and their URL path prefixes.
operationPaths :: Map Text Text
operationPaths = Map.fromList
  [ ("PurchaseHistoryV2", "/orchestra/cph/graphql/PurchaseHistoryV2/")
  ]

-- | Seed hash for getOrder (server-side persisted query, not in frontend JS).
seedGetOrderHash :: Text
seedGetOrderHash = "d0622497daef19150438d07c506739d451cad6749cf45c3b4db95f2f5a0a65c4"

-- | Discovered endpoint URLs.
data Endpoints = Endpoints
  { epPurchaseHistory :: Text
  , epGetOrder        :: Text
  } deriving stock (Show)

-- | Discover current endpoint URLs by scraping Walmart's JS bundles.
-- Requires lightpanda on PATH.
discoverEndpoints :: Manager -> IO Endpoints
discoverEndpoints mgr = do
  html <- T.pack <$> renderOrdersPage
  let scriptUrls = parseScriptUrls html
  hashes <- scanChunks mgr scriptUrls (Map.keysSet operationPaths)
  let purchaseHash = hashes Map.! "PurchaseHistoryV2"
  pure Endpoints
    { epPurchaseHistory = walmartBase <> "/orchestra/cph/graphql/PurchaseHistoryV2/" <> purchaseHash
    , epGetOrder = walmartBase <> "/orchestra/orders/graphql/getOrder/" <> seedGetOrderHash
    }

renderOrdersPage :: IO String
renderOrdersPage =
  readProcess "lightpanda"
    ["fetch", "--dump", "html", T.unpack walmartBase <> "/orders"] ""

-- | Extract walmartimages.com JS script URLs from HTML.
parseScriptUrls :: Text -> [Text]
parseScriptUrls = collectAll scriptUrlParser

scriptUrlParser :: A.Parser Text
scriptUrlParser = do
  _ <- A.manyTill A.anyChar (A.string "src=\"https://i5.walmartimages.com")
  let prefix = "https://i5.walmartimages.com"
  rest <- A.takeWhile (/= '"')
  _ <- A.char '"'
  if T.isSuffixOf ".js" rest
    then pure (prefix <> rest)
    else fail "not a JS URL"

-- | Extract name/hash pairs from webpack JS chunks.
parseHashPair :: A.Parser (Text, Text)
parseHashPair = do
  _ <- A.manyTill A.anyChar (A.string "name:\"")
  name <- A.takeWhile1 (\c -> c /= '"')
  _ <- A.string "\",hash:\""
  hash <- A.take 64
  _ <- A.char '"'
  if T.all isHexDigit hash
    then pure (name, hash)
    else fail "not a valid hash"
  where
    isHexDigit c = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')

-- | Run a parser repeatedly, collecting all successful matches.
collectAll :: A.Parser a -> Text -> [a]
collectAll p input = case A.parse p input of
  A.Done rest val -> val : collectAll p rest
  A.Partial cont  -> case cont "" of
    A.Done rest val -> val : collectAll p rest
    A.Partial _     -> []
    A.Fail {}       -> []
  A.Fail rest _ _ -> case T.uncons rest of
    Just (_, rest') -> collectAll p rest'
    Nothing         -> []

scanChunks :: Manager -> [Text] -> Set Text -> IO (Map Text Text)
scanChunks mgr urls targets = go urls Map.empty targets
  where
    go [] found _ = pure found
    go _ found remaining | Set.null remaining = pure found
    go (url : rest) found remaining = do
      req <- parseRequest (T.unpack url)
      resp <- httpLbs req mgr
      let body = TE.decodeUtf8Lenient (LBS.toStrict (responseBody resp))
          pairs = collectAll parseHashPair body
          newFound = Map.fromList
            [(n, h) | (n, h) <- pairs, Set.member n remaining]
          found' = Map.union found newFound
          remaining' = Set.difference remaining (Map.keysSet newFound)
      go rest found' remaining'

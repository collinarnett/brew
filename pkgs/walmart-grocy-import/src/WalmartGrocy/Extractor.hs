{-# LANGUAGE OverloadedStrings #-}

-- | Endpoint hash discovery and caching.
module WalmartGrocy.Extractor
  ( resolveEndpoints
  , invalidateCache
    -- * Parsers (exported for testing)
  , parseScriptUrls
  , parseHashPair
  , collectAll
  ) where

import Data.Aeson qualified as Aeson
import Data.Attoparsec.Text qualified as A
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Network.HTTP.Client (Manager, httpLbs, parseRequest, responseBody)
import System.Directory (doesFileExist, removeFile)
import System.FilePath ((</>))
import System.Process (readProcess)

import WalmartGrocy.Types

walmartBase :: Text
walmartBase = "https://www.walmart.com"

operationPaths :: Map Text Text
operationPaths = Map.fromList
  [ ("PurchaseHistoryV2", "/orchestra/cph/graphql/PurchaseHistoryV2/")
  ]

seedGetOrderHash :: Text
seedGetOrderHash = "d0622497daef19150438d07c506739d451cad6749cf45c3b4db95f2f5a0a65c4"

cacheTtlSeconds :: Double
cacheTtlSeconds = 86400

resolveEndpoints :: Manager -> FilePath -> IO (Map Text EndpointUrl)
resolveEndpoints mgr cacheDir = do
  cached <- loadCache cacheDir
  case cached of
    Just endpoints -> pure endpoints
    Nothing        -> discoverAndCache mgr cacheDir

invalidateCache :: FilePath -> IO ()
invalidateCache cacheDir = do
  let path = cacheDir </> "endpoints.json"
  exists <- doesFileExist path
  if exists then removeFile path else pure ()

-- Internal

loadCache :: FilePath -> IO (Maybe (Map Text EndpointUrl))
loadCache cacheDir = do
  let path = cacheDir </> "endpoints.json"
  exists <- doesFileExist path
  if not exists
    then pure Nothing
    else do
      contents <- LBS.readFile path
      case Aeson.eitherDecode contents of
        Left _   -> pure Nothing
        Right ec -> do
          now <- getCurrentTime
          let age = realToFrac (diffUTCTime now (ecTimestamp ec))
          if age > cacheTtlSeconds
            then pure Nothing
            else pure (Just (ecEndpoints ec))

discoverAndCache :: Manager -> FilePath -> IO (Map Text EndpointUrl)
discoverAndCache mgr cacheDir = do
  html <- T.pack <$> renderOrdersPage
  let scriptUrls = parseScriptUrls html
  hashes <- scanChunks mgr scriptUrls (Map.keysSet operationPaths)
  let discovered = Map.mapWithKey buildUrl hashes
      getOrderUrl = EndpointUrl
        (walmartBase <> "/orchestra/orders/graphql/getOrder/" <> seedGetOrderHash)
      endpoints = Map.insert "getOrder" getOrderUrl discovered
  saveCache cacheDir endpoints
  pure endpoints

buildUrl :: Text -> Text -> EndpointUrl
buildUrl opName hash =
  case Map.lookup opName operationPaths of
    Just path -> EndpointUrl (walmartBase <> path <> hash)
    Nothing   -> EndpointUrl (walmartBase <> "/" <> opName <> "/" <> hash)

renderOrdersPage :: IO String
renderOrdersPage =
  readProcess "lightpanda"
    ["fetch", "--dump", "html", T.unpack walmartBase <> "/orders"] ""

-- | Parser: extract all walmartimages.com JS script URLs from HTML.
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

-- | Parser: extract name/hash pairs from webpack JS chunks.
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
    _               -> []
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

saveCache :: FilePath -> Map Text EndpointUrl -> IO ()
saveCache cacheDir endpoints = do
  now <- getCurrentTime
  let cache = EndpointCache { ecTimestamp = now, ecEndpoints = endpoints }
      path = cacheDir </> "endpoints.json"
  LBS.writeFile path (Aeson.encode cache)

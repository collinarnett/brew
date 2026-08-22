{-# LANGUAGE OverloadedStrings #-}

-- | Recovering Walmart's current persisted query hashes.
--
-- Walmart's homepage names the asset base its own scripts load from.
-- That base leads to the build manifest, the manifest and the page
-- between them name the chunks, and the chunks carry the hashes. Every
-- step after the first reads an unauthenticated CDN.
module Walmart.Discovery
  ( DiscoveryError (..)
  , renderDiscoveryError
  , discover
  , pageCandidates
  ) where

import Control.Concurrent.QSem (newQSem, signalQSem, waitQSem)
import Control.Exception (bracket_, displayException, try)
import Control.Concurrent.Async (mapConcurrently)
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (getCurrentTime)
import Network.HTTP.Client
  ( HttpException
  , Manager
  , httpLbs
  , parseRequest
  , requestHeaders
  , responseBody
  , responseStatus
  )
import Network.HTTP.Types.Status (statusCode)

import Walmart.Catalog
  ( BuildId (..)
  , Catalog
  , CatalogEntry (..)
  , Origin (..)
  , catalogSize
  , emptyCatalog
  , insertEntry
  )
import Walmart.Discovery.Parse
  ( AssetBase (..)
  , ChunkPath (..)
  , parseAssetBase
  , parseBuildId
  , parseBuildManifestUrl
  , parseHtmlChunks
  , parseManifestChunks
  , parseOperationHashes
  )
import Walmart.Types (OperationName, QueryHash)

-- | Pages that state the current build. Walmart serves the site root to
-- an ordinary client; most other paths answer with a redirect, so the
-- list is ordered and tried until one yields a build.
pageCandidates :: [Text]
pageCandidates =
  [ "https://www.walmart.com/"
  , "https://www.walmart.com/all-departments"
  ]

data DiscoveryError
    -- | No candidate page yielded an asset base, with the reason each
    -- one failed.
  = BuildUnlocated [(Text, Text)]
  | ManifestUnreadable Text Text
  | BuildIdUnparsed Text
    -- | Chunks were fetched but none registered a persisted query,
    -- which means the shape they are scanned for has moved.
  | NoOperationsFound BuildId Int
  deriving stock (Show, Eq)

renderDiscoveryError :: DiscoveryError -> Text
renderDiscoveryError (BuildUnlocated attempts) =
  "Could not locate Walmart's current frontend build.\n"
  <> T.unlines [ "  " <> url <> ": " <> reason | (url, reason) <- attempts ]
renderDiscoveryError (ManifestUnreadable url reason) =
  "Could not read the build manifest at " <> url <> ": " <> reason
renderDiscoveryError (BuildIdUnparsed url) =
  "Build manifest URL does not name a build: " <> url
renderDiscoveryError (NoOperationsFound build scanned) =
  "Scanned " <> T.pack (show scanned) <> " chunks of build "
  <> unBuildId build <> " and found no persisted queries."

-- | How many chunk fetches run at once. Discovery reads several hundred
-- small files, and Walmart's CDN serves them without complaint at this
-- width.
fetchWidth :: Int
fetchWidth = 12

discover :: Manager -> IO (Either DiscoveryError Catalog)
discover mgr = do
  located <- locateBuild mgr pageCandidates []
  case located of
    Left err -> pure (Left err)
    Right (base, html, manifestUrl) -> case parseBuildId manifestUrl of
      Nothing -> pure (Left (BuildIdUnparsed manifestUrl))
      Just build -> do
        manifest <- fetchText mgr manifestUrl
        case manifest of
          Left reason -> pure (Left (ManifestUnreadable manifestUrl reason))
          Right manifestBody -> do
            let chunks = dedupe (parseManifestChunks manifestBody <> parseHtmlChunks base html)
            now <- getCurrentTime
            pairs <- scanChunks mgr base chunks
            let catalog = foldr (insertEntry . toEntry build now) emptyCatalog pairs
            pure $ if catalogSize catalog == 0
              then Left (NoOperationsFound build (length chunks))
              else Right catalog
  where
    toEntry build now (name, hash) = CatalogEntry
      { entryName   = name
      , entryHash   = hash
      , entryOrigin = Discovered build now
      }

dedupe :: [ChunkPath] -> [ChunkPath]
dedupe = Map.elems . Map.fromList . map (\c -> (unChunkPath c, c))

locateBuild
  :: Manager -> [Text] -> [(Text, Text)]
  -> IO (Either DiscoveryError (AssetBase, Text, Text))
locateBuild _ [] attempts = pure (Left (BuildUnlocated (reverse attempts)))
locateBuild mgr (url : rest) attempts = do
  fetched <- fetchText mgr url
  case fetched of
    Left reason -> locateBuild mgr rest ((url, reason) : attempts)
    Right html -> case (parseAssetBase html, parseBuildManifestUrl html) of
      (Just base, Just manifestUrl) -> pure (Right (base, html, manifestUrl))
      _missingCoordinates ->
        locateBuild mgr rest ((url, "no asset base in the response") : attempts)

scanChunks :: Manager -> AssetBase -> [ChunkPath] -> IO [(OperationName, QueryHash)]
scanChunks mgr (AssetBase base) chunks = do
  gate <- newQSem fetchWidth
  results <- mapConcurrently (withGate gate . scanOne) chunks
  pure (concat results)
  where
    withGate gate = bracket_ (waitQSem gate) (signalQSem gate)
    scanOne (ChunkPath path) = do
      fetched <- fetchText mgr (base <> path)
      pure $ case fetched of
        -- A chunk that will not load costs its operations, never the
        -- run: the remaining hundreds still carry theirs.
        Left _unreachable -> []
        Right body -> parseOperationHashes body

fetchText :: Manager -> Text -> IO (Either Text Text)
fetchText mgr url = do
  attempt <- try $ do
    req0 <- parseRequest (T.unpack url)
    let req = req0 { requestHeaders = [("user-agent", "walmart-mcp endpoint discovery")] }
    httpLbs req mgr
  pure $ case attempt of
    Left err -> Left (T.pack (displayException (err :: HttpException)))
    Right resp ->
      let code = statusCode (responseStatus resp)
      in if code == 200
           then Right (TE.decodeUtf8Lenient (LBS.toStrict (responseBody resp)))
           else Left ("HTTP " <> T.pack (show code))

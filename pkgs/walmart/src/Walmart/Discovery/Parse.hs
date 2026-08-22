{-# LANGUAGE OverloadedStrings #-}

-- | Pure parsers over Walmart's frontend assets.
--
-- Nothing here performs IO, so every rule about where a build lives and
-- what a persisted query looks like can be exercised against saved
-- documents.
module Walmart.Discovery.Parse
  ( AssetBase (..)
  , ChunkPath (..)
  , parseAssetBase
  , parseBuildManifestUrl
  , parseBuildId
  , parseHtmlChunks
  , parseManifestChunks
  , parseOperationHashes
    -- * Building blocks
  , collectAll
  , assetUrlParser
  , quotedChunkParser
  , hashPairParser
  ) where

import Data.Attoparsec.Text qualified as A
import Data.List (nub)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T

import Walmart.Catalog (BuildId (..))
import Walmart.Types (OperationName (..), QueryHash, mkQueryHash)

-- | Everything Walmart's frontend assets hang off, up to and including
-- the @_next/@ segment, so a chunk path appends directly.
newtype AssetBase = AssetBase { unAssetBase :: Text }
  deriving stock (Show, Eq)

-- | A chunk location relative to an 'AssetBase'.
newtype ChunkPath = ChunkPath { unChunkPath :: Text }
  deriving stock (Show, Eq, Ord)

assetHost :: Text
assetHost = "https://i5.walmartimages.com"

nextMarker :: Text
nextMarker = "/_next/"

-- | Every asset-host URL the document mentions.
assetUrlParser :: A.Parser Text
assetUrlParser = do
  _ <- A.manyTill A.anyChar (A.string assetHost)
  rest <- A.takeWhile (\c -> c `notElem` ("\"'\\ <>" :: String))
  pure (assetHost <> rest)

-- | The asset base the document's own scripts are served from.
parseAssetBase :: Text -> Maybe AssetBase
parseAssetBase html =
  case filter (T.isInfixOf nextMarker) (collectAll assetUrlParser html) of
    []      -> Nothing
    url : _ ->
      let (before, _) = T.breakOn nextMarker url
      in Just (AssetBase (before <> nextMarker))

parseBuildManifestUrl :: Text -> Maybe Text
parseBuildManifestUrl html =
  case filter (T.isSuffixOf "_buildManifest.js") (collectAll assetUrlParser html) of
    []      -> Nothing
    url : _ -> Just url

-- | The build id names the directory the manifest is served from.
parseBuildId :: Text -> Maybe BuildId
parseBuildId manifestUrl =
  case reverse (T.splitOn "/" manifestUrl) of
    _file : build : _ | not (T.null build) -> Just (BuildId build)
    _otherShape -> Nothing

-- | Chunks the document loads directly. The build manifest does not
-- list every one of them, so both sources are read.
parseHtmlChunks :: AssetBase -> Text -> [ChunkPath]
parseHtmlChunks (AssetBase base) html =
  nub
    [ ChunkPath rest
    | url <- collectAll assetUrlParser html
    , T.isSuffixOf ".js" url
    , Just rest <- [T.stripPrefix base url]
    ]

-- | Chunk paths named by a @_buildManifest.js@ document.
parseManifestChunks :: Text -> [ChunkPath]
parseManifestChunks = nub . map ChunkPath . collectAll quotedChunkParser

quotedChunkParser :: A.Parser Text
quotedChunkParser = do
  _ <- A.manyTill A.anyChar (A.char '"')
  body <- A.takeWhile (/= '"')
  _ <- A.char '"'
  if T.isPrefixOf "static/" body && T.isSuffixOf ".js" body
    then pure body
    else fail "not a chunk path"

-- | Persisted query registrations found in a chunk.
parseOperationHashes :: Text -> [(OperationName, QueryHash)]
parseOperationHashes = mapMaybe toEntry . collectAll hashPairParser
  where
    toEntry (name, rawHash) =
      (,) (OperationName name) <$> mkQueryHash rawHash

-- | A @name:"...",hash:"..."@ registration. The hash is returned raw:
-- 'mkQueryHash' decides what counts as one, and 'parseOperationHashes'
-- drops whatever it refuses.
hashPairParser :: A.Parser (Text, Text)
hashPairParser = do
  _ <- A.manyTill A.anyChar (A.string "name:\"")
  name <- A.takeWhile1 (/= '"')
  _ <- A.string "\",hash:\""
  hash <- A.take 64
  _ <- A.char '"'
  pure (name, hash)

-- | Run a parser repeatedly, collecting every match.
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

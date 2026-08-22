{-# LANGUAGE OverloadedStrings #-}

-- | Saved Walmart documents the parsers are exercised against.
--
-- Every build here was captured from a different Walmart release. The
-- parsers are written against one of them and must handle the rest
-- unseen, which is what stops them from fitting a single build.
module Corpus
  ( Build (..)
  , realBuilds
  , refusals
  , chunkFiles
  , searchResponseFile
  , mixedTilesFile
  , readCorpus
  ) where

import Data.Text (Text)
import Data.ByteString qualified as BS
import Data.Text.Encoding qualified as TE
import System.FilePath ((</>))

data Build = Build
  { buildLabel :: String
  , buildFile  :: FilePath
  } deriving stock (Show)

corpusRoot :: FilePath
corpusRoot = "test" </> "corpus"

-- | Captures that contain a real Walmart page.
realBuilds :: [Build]
realBuilds =
  [ Build "2025-05-29" (corpusRoot </> "builds" </> "2025-05-29.html")
  , Build "2026-07-07" (corpusRoot </> "builds" </> "2026-07-07.html")
  , Build "2025-10-07" (corpusRoot </> "builds" </> "2025-10-07.html")
  , Build "2026-04-09" (corpusRoot </> "builds" </> "2026-04-09.html")
  , Build "2026-08-20" (corpusRoot </> "builds" </> "2026-08-20.html")
  ]

-- | What Walmart sends when it declines to serve the page. Discovery
-- must report that it found nothing in these rather than inventing
-- coordinates.
refusals :: [(String, FilePath)]
refusals =
  [ ("akamai redirect", corpusRoot </> "builds" </> "refused-akamai-redirect.html")
  , ("perimeterx challenge", corpusRoot </> "builds" </> "refused-perimeterx.json")
  ]

chunkFiles :: [FilePath]
chunkFiles =
  [ corpusRoot </> "chunks" </> "2026-04-09-account.js"
  , corpusRoot </> "chunks" </> "2026-08-20-orders.js"
  ]

searchResponseFile :: FilePath
searchResponseFile = corpusRoot </> "search" </> "milk-2026-08-22.json"

-- | A wider search, whose stack mixes real products with the ad and
-- placeholder tiles Walmart returns alongside them.
mixedTilesFile :: FilePath
mixedTilesFile = corpusRoot </> "search" </> "milk-mixed-tiles-2026-08-22.json"

-- | Corpus documents are read exactly as the client reads a response:
-- bytes decoded leniently, because a Walmart asset is not guaranteed to
-- be valid UTF-8.
readCorpus :: FilePath -> IO Text
readCorpus path = TE.decodeUtf8Lenient <$> BS.readFile path

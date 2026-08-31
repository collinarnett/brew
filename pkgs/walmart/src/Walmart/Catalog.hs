{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The persisted query hashes this client knows, and where each came
-- from.
--
-- The catalog is data the program maintains, never source it is
-- compiled with: nothing here is written by hand, and 'adoptDiscovered'
-- is the only way new hashes arrive.
module Walmart.Catalog
  ( Catalog
  , CatalogEntry (..)
  , Origin (..)
  , BuildId (..)
  , emptyCatalog
  , catalogEntries
  , catalogSize
  , lookupOperation
  , insertEntry
  , seededCatalog
  , adoptDiscovered
  , loadCatalog
  , saveCatalog
  , defaultCatalogPath
  , CatalogError (..)
  , renderCatalogError
  ) where

import Data.Aeson
  ( FromJSON (..)
  , ToJSON (..)
  , Object
  , eitherDecodeFileStrict'
  , encodeFile
  , object
  , withObject
  , withText
  , (.:)
  , (.=)
  )
import Data.Aeson.Types (Parser)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import System.Directory
  ( XdgDirectory (XdgState)
  , createDirectoryIfMissing
  , doesFileExist
  , getXdgDirectory
  )
import System.FilePath (takeDirectory, (</>))

import Walmart.Types (OperationName (..), QueryHash, mkQueryHash)

-- | The frontend release a hash was scanned out of.
newtype BuildId = BuildId { unBuildId :: Text }
  deriving stock (Show, Eq, Ord)

-- | How an entry came to be known. Discovery records the build and the
-- time it ran; a seeded entry has neither, because it was supplied by
-- configuration rather than found.
data Origin
  = Discovered BuildId UTCTime
  | Seeded
  deriving stock (Show, Eq)

data CatalogEntry = CatalogEntry
  { entryName   :: OperationName
  , entryHash   :: QueryHash
  , entryOrigin :: Origin
  } deriving stock (Show, Eq)

newtype Catalog = Catalog (Map OperationName CatalogEntry)
  deriving stock (Show, Eq)

emptyCatalog :: Catalog
emptyCatalog = Catalog Map.empty

catalogEntries :: Catalog -> [CatalogEntry]
catalogEntries (Catalog m) = Map.elems m

catalogSize :: Catalog -> Int
catalogSize (Catalog m) = Map.size m

lookupOperation :: Catalog -> OperationName -> Maybe CatalogEntry
lookupOperation (Catalog m) name = Map.lookup name m

-- | Hashes supplied by configuration, for operations discovery cannot
-- see. They sit under anything discovery finds.
seededCatalog :: [(OperationName, QueryHash)] -> Catalog
seededCatalog pairs = Catalog (Map.fromList (map entry pairs))
  where
    entry (name, hash) =
      (name, CatalogEntry { entryName = name, entryHash = hash, entryOrigin = Seeded })

insertEntry :: CatalogEntry -> Catalog -> Catalog
insertEntry entry (Catalog m) = Catalog (Map.insert (entryName entry) entry m)

-- | Fold a discovery run over what is already known.
--
-- Discovery reads the frontend bundles, which do not carry every
-- operation Walmart's gateway serves. Entries it did not find are kept,
-- so a refresh can only ever add and update.
adoptDiscovered :: Catalog -> Catalog -> Catalog
adoptDiscovered (Catalog discovered) (Catalog known) =
  Catalog (Map.union discovered known)

instance ToJSON CatalogEntry where
  toJSON entry = object $
    [ "name" .= entryName entry
    , "hash" .= entryHash entry
    ] <> originFields (entryOrigin entry)
    where
      originFields Seeded = [ "origin" .= ("seeded" :: Text) ]
      originFields (Discovered build at) =
        [ "origin"     .= ("discovered" :: Text)
        , "build"      .= unBuildId build
        , "fetched_at" .= at
        ]

instance FromJSON CatalogEntry where
  parseJSON = withObject "CatalogEntry" $ \o -> do
    name <- OperationName <$> o .: "name"
    hash <- parseHash =<< o .: "hash"
    origin <- parseOrigin o
    pure CatalogEntry { entryName = name, entryHash = hash, entryOrigin = origin }

parseHash :: Text -> Parser QueryHash
parseHash raw = case mkQueryHash raw of
  Just h  -> pure h
  Nothing -> fail ("not a persisted query hash: " <> show raw)

parseOrigin :: Object -> Parser Origin
parseOrigin o = do
  tag <- o .: "origin"
  flip (withText "origin") tag $ \case
    "seeded" -> pure Seeded
    "discovered" -> do
      build <- BuildId <$> o .: "build"
      at    <- o .: "fetched_at"
      pure (Discovered build at)
    other -> fail ("unknown origin: " <> show other)

instance ToJSON Catalog where
  toJSON cat = object
    [ "version"    .= (1 :: Int)
    , "operations" .= catalogEntries cat
    ]

instance FromJSON Catalog where
  parseJSON = withObject "Catalog" $ \o -> do
    version <- o .: "version" :: Parser Int
    if version /= 1
      then fail ("unsupported catalog version: " <> show version)
      else do
        entries <- o .: "operations"
        pure (Catalog (Map.fromList [(entryName e, e) | e <- entries]))

data CatalogError
  = CatalogUnreadable FilePath String
  deriving stock (Show, Eq)

renderCatalogError :: CatalogError -> Text
renderCatalogError (CatalogUnreadable path err) =
  "Could not read the endpoint catalog at " <> T.pack path <> ": " <> T.pack err

defaultCatalogPath :: IO FilePath
defaultCatalogPath = do
  stateDir <- getXdgDirectory XdgState "walmart"
  pure (stateDir </> "catalog.json")

-- | Read the catalog, treating a missing file as an empty one. A file
-- that exists but does not parse is an error: silently starting over
-- would discard seeded entries that cannot be rediscovered.
loadCatalog :: FilePath -> IO (Either CatalogError Catalog)
loadCatalog path = do
  exists <- doesFileExist path
  if not exists
    then pure (Right emptyCatalog)
    else do
      decoded <- eitherDecodeFileStrict' path
      pure $ case decoded of
        Left err  -> Left (CatalogUnreadable path err)
        Right cat -> Right cat

saveCatalog :: FilePath -> Catalog -> IO ()
saveCatalog path cat = do
  createDirectoryIfMissing True (takeDirectory path)
  encodeFile path cat

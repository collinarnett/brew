{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.List (nub, sort)
import Data.Maybe (isJust, isNothing, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Test.QuickCheck
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck (testProperty)

import Corpus
import Walmart.Catalog
import Walmart.Discovery.Parse
import Walmart.Operation
import Walmart.Response (graphQLRejection, parseSearchResult)
import Walmart.Types

main :: IO ()
main = do
  builds <- traverse (\b -> (,) b <$> readCorpus (buildFile b)) realBuilds
  refused <- traverse (\(name, path) -> (,) name <$> readCorpus path) refusals
  chunks <- traverse readCorpus chunkFiles
  searchBody <- Aeson.eitherDecodeFileStrict' searchResponseFile
  mixedBody <- Aeson.eitherDecodeFileStrict' mixedTilesFile
  defaultMain $ testGroup "walmart"
    [ buildTests builds refused
    , chunkTests chunks
    , hashParserTests
    , catalogTests
    , searchTests searchBody
    , mixedTileTests mixedBody
    , rejectionTests
    , fulfillmentTests
    , storeTests mixedBody
    ]

-- | Every real capture must yield a build, and no two captures may
-- yield the same one: if they did, the corpus would not be exercising
-- rotation at all.
buildTests :: [(Build, Text)] -> [(String, Text)] -> TestTree
buildTests builds refused = testGroup "Build location"
  [ testGroup "each captured build parses"
      [ testCase (buildLabel b) $ do
          assertBool "asset base" (isJust (parseAssetBase html))
          assertBool "manifest url" (isJust (parseBuildManifestUrl html))
          assertBool "build id" (isJust (parseBuildManifestUrl html >>= parseBuildId))
          assertBool "chunks named" $ case parseAssetBase html of
            Nothing   -> False
            Just base -> not (null (parseHtmlChunks base html))
      | (b, html) <- builds
      ]

  , testCase "captures come from distinct builds" $ do
      let ids = mapMaybe (\(_, html) -> unBuildId <$> (parseBuildManifestUrl html >>= parseBuildId)) builds
      length (nub ids) @?= length builds

  , testGroup "a refusal yields nothing"
      [ testCase refusalName $ do
          assertBool "invented an asset base" (isNothing (parseAssetBase body))
          assertBool "invented a manifest url" (isNothing (parseBuildManifestUrl body))
      | (refusalName, body) <- refused
      ]
  ]

chunkTests :: [Text] -> TestTree
chunkTests chunks = testGroup "Chunk scanning"
  [ testCase "every captured chunk registers a persisted query" $
      mapM_ (\c -> assertBool "no registrations" (not (null (parseOperationHashes c)))) chunks

  , testCase "an empty document registers nothing" $
      parseOperationHashes "" @?= []

  , testCase "scanning is unaffected by how chunks are grouped" $ do
      let separately = concatMap parseOperationHashes chunks
          together   = parseOperationHashes (T.intercalate "\n" chunks)
      sort (map (unOperationName . fst) separately)
        @?= sort (map (unOperationName . fst) together)

  , testCase "scanning the same document twice agrees with itself" $
      mapM_ (\c -> parseOperationHashes c @?= parseOperationHashes c) chunks
  ]

hashParserTests :: TestTree
hashParserTests = testGroup "Hash rejection"
  [ testCase "uppercase hex is not a hash" $
      parseOperationHashes ("name:\"Foo\",hash:\"" <> T.replicate 64 "A" <> "\"") @?= []

  , testCase "63 characters is not a hash" $
      parseOperationHashes ("name:\"Foo\",hash:\"" <> T.replicate 63 "a" <> "\"") @?= []

  , testCase "a name without a hash registers nothing" $
      parseOperationHashes "name:\"Foo\",value:\"bar\"" @?= []

  , testCase "mkQueryHash agrees with the parser" $ do
      assertBool "64 lowercase hex accepted" (isJust (mkQueryHash (T.replicate 64 "a")))
      assertBool "uppercase rejected" (isNothing (mkQueryHash (T.replicate 64 "A")))
      assertBool "short rejected" (isNothing (mkQueryHash (T.replicate 63 "a")))
      assertBool "long rejected" (isNothing (mkQueryHash (T.replicate 65 "a")))

  , testProperty "a well-formed registration is always recovered" $
      \(AlphaName name, HexHash hash) ->
        let input = "junk name:\"" <> name <> "\",hash:\"" <> hash <> "\" junk"
        in map (\(n, h) -> (unOperationName n, unQueryHash h)) (parseOperationHashes input)
             == [(name, hash)]

  , testProperty "arbitrary text never crashes the scanner" $
      \s -> length (parseOperationHashes (T.pack s)) >= 0
  ]

newtype AlphaName = AlphaName Text deriving stock (Show)
instance Arbitrary AlphaName where
  arbitrary = AlphaName . T.pack <$> listOf1 (elements (['a'..'z'] <> ['A'..'Z']))

newtype HexHash = HexHash Text deriving stock (Show)
instance Arbitrary HexHash where
  arbitrary = HexHash . T.pack <$> vectorOf 64 (elements (['0'..'9'] <> ['a'..'f']))

-- | A hash literal the test itself vouches for, so a typo in a fixture
-- fails the test rather than the pattern match.
requireHash :: Text -> IO QueryHash
requireHash raw = maybe (assertFailure ("not a hash: " <> T.unpack raw)) pure (mkQueryHash raw)

catalogTests :: TestTree
catalogTests = testGroup "Catalog"
  [ testCase "a discovery run never drops what it cannot see" $ do
      seedHash <- requireHash (T.replicate 64 "a")
      freshHash <- requireHash (T.replicate 64 "b")
      let seeds = seededCatalog [(operationName GetOrder, seedHash)]
          discovered = seededCatalog [(operationName Search, freshHash)]
          merged = adoptDiscovered discovered seeds
      catalogSize merged @?= 2
      fmap entryHash (lookupOperation merged GetOrder) @?= Just seedHash
      fmap entryHash (lookupOperation merged Search) @?= Just freshHash

  , testCase "discovery wins over a seed for the same operation" $ do
      seedHash <- requireHash (T.replicate 64 "a")
      freshHash <- requireHash (T.replicate 64 "b")
      let merged = adoptDiscovered
            (seededCatalog [(operationName Search, freshHash)])
            (seededCatalog [(operationName Search, seedHash)])
      fmap entryHash (lookupOperation merged Search) @?= Just freshHash

  , testCase "a catalog survives a JSON round trip" $ do
      hash <- requireHash (T.replicate 64 "c")
      let catalog = seededCatalog [(operationName Search, hash)]
      Aeson.eitherDecode (Aeson.encode catalog) @?= Right catalog

  , testCase "a hash that is not 64 hex characters is refused on load" $ do
      let bad = "{\"version\":1,\"operations\":[{\"name\":\"Search\",\"hash\":\"nope\",\"origin\":\"seeded\"}]}"
      assertBool "decoded a malformed hash" $
        case Aeson.eitherDecode bad :: Either String Catalog of
          Left _  -> True
          Right _ -> False

  , testCase "every operation has a distinct gateway name" $ do
      let names = map (unOperationName . operationName) allOperations
      length (nub names) @?= length names
  ]

searchTests :: Either String Aeson.Value -> TestTree
searchTests (Left err) = testCase "search corpus decodes" (assertFailure err)
searchTests (Right body) = testGroup "Search response"
  [ testCase "every result carries an id and a name" $
      case parseSearchResult body of
        Left err -> assertFailure err
        Right result -> do
          assertBool "no products parsed" (not (null (srProducts result)))
          mapM_ (\p -> do
                   assertBool "empty item id" (not (T.null (unUsItemId (psUsItemId p))))
                   assertBool "empty name" (not (T.null (psName p))))
                (srProducts result)

  , testCase "prices are recovered as whole cents" $
      case parseSearchResult body of
        Left err -> assertFailure err
        Right result -> do
          let priced = mapMaybe psPrice (srProducts result)
          assertBool "no prices parsed" (not (null priced))
          mapM_ (\c -> assertBool "non-positive price" (toInteger c > 0)) priced

  , testCase "the department facet names a category id" $
      case parseSearchResult body of
        Left err -> assertFailure err
        Right result -> do
          let names = map cfName (srCategories result)
          assertBool ("no categories in " <> show names) (not (null (srCategories result)))
          mapM_ (\c -> assertBool "empty category id" (not (T.null (unCategoryId (cfId c)))))
                (srCategories result)
  ]

-- | Walmart signals a hash it will not serve with a GraphQL errors body
-- under HTTP 200, so recognising that shape is what makes the catalog
-- refresh itself rather than surfacing a parse failure.
rejectionTests :: TestTree
rejectionTests = testGroup "Rejection detection"
  [ rejectionCase "errors without data is a rejection"
      "{\"errors\":[{\"message\":\"boom\"}]}" (Just "boom")

  , rejectionCase "several errors are all reported"
      "{\"errors\":[{\"message\":\"a\"},{\"message\":\"b\"}]}" (Just "a; b")

  , rejectionCase "data alongside errors is a partial success, not a rejection"
      "{\"data\":{\"x\":1},\"errors\":[{\"message\":\"boom\"}]}" Nothing

  , rejectionCase "a plain response is not a rejection"
      "{\"data\":{\"x\":1}}" Nothing

  , testCase "the captured search response is not a rejection" $ do
      body <- Aeson.eitherDecodeFileStrict' searchResponseFile
      either assertFailure (\v -> graphQLRejection v @?= Nothing) body
  ]

rejectionCase :: String -> LBS.ByteString -> Maybe Text -> TestTree
rejectionCase name raw expected = testCase name $
  case Aeson.eitherDecode raw of
    Left err    -> assertFailure ("fixture is not JSON: " <> err)
    Right value -> graphQLRejection value @?= expected

-- | Walmart pads a search stack with ad and placeholder tiles that
-- carry no item. They are not products and must not be mistaken for a
-- malformed one.
mixedTileTests :: Either String Aeson.Value -> TestTree
mixedTileTests (Left err) = testCase "mixed-tile corpus decodes" (assertFailure err)
mixedTileTests (Right body) = testGroup "Non-product tiles"
  [ testCase "products are recovered and placeholders skipped" $
      case parseSearchResult body of
        Left err -> assertFailure err
        Right result -> length (srProducts result) @?= 24

  , testCase "every recovered tile still has an id and a name" $
      case parseSearchResult body of
        Left err -> assertFailure err
        Right result -> mapM_
          (\p -> do
             assertBool "empty item id" (not (T.null (unUsItemId (psUsItemId p))))
             assertBool "empty name" (not (T.null (psName p))))
          (srProducts result)
  ]

-- | Build a search response around one product tile.
searchCase :: String -> LBS.ByteString -> (SearchResult -> Assertion) -> TestTree
searchCase name raw check = testCase name $
  case Aeson.eitherDecode raw of
    Left err -> assertFailure ("fixture is not JSON: " <> err)
    Right value -> either assertFailure check (parseSearchResult value)

-- | Walmart lists a fulfillment method once per slot, mostly undated,
-- so the same method arrives several times in one item.
fulfillmentTests :: TestTree
fulfillmentTests = testGroup "Fulfillment"
  [ searchCase "repeated methods collapse to the soonest offer"
      "{\"data\":{\"search\":{\"searchResult\":{\"itemStacks\":[{\"itemsV2\":[\
       \{\"__typename\":\"Product\",\"usItemId\":\"1\",\"name\":\"x\",\"fulfillmentSummary\":[\
       \{\"fulfillment\":\"DELIVERY\",\"deliveryDate\":null},\
       \{\"fulfillment\":\"DELIVERY\",\"deliveryDate\":\"2026-08-24T22:00:00.000Z\"},\
       \{\"fulfillment\":\"DELIVERY\",\"deliveryDate\":\"2026-08-22T22:00:00.000Z\"},\
       \{\"fulfillment\":\"PICKUP\",\"deliveryDate\":\"2026-08-21T10:00:00.000Z\"}]}]}]}}}}"
      (\r -> case srProducts r of
         [p] -> map foMethod (psFulfillment p) @?= [Delivery, Pickup]
         other -> assertFailure ("expected one product, got " <> show (length other)))

  , searchCase "the soonest date wins for a repeated method"
      "{\"data\":{\"search\":{\"searchResult\":{\"itemStacks\":[{\"itemsV2\":[\
       \{\"__typename\":\"Product\",\"usItemId\":\"1\",\"name\":\"x\",\"fulfillmentSummary\":[\
       \{\"fulfillment\":\"DELIVERY\",\"deliveryDate\":\"2026-08-24T22:00:00.000Z\"},\
       \{\"fulfillment\":\"DELIVERY\",\"deliveryDate\":\"2026-08-22T22:00:00.000Z\"}]}]}]}}}}"
      (\r -> case concatMap psFulfillment (srProducts r) of
         [o] -> fmap show (foEarliest o) @?= Just "2026-08-22 22:00:00 UTC"
         other -> assertFailure ("expected one option, got " <> show (length other)))

  , searchCase "an unfamiliar method is carried, not rejected"
      "{\"data\":{\"search\":{\"searchResult\":{\"itemStacks\":[{\"itemsV2\":[\
       \{\"__typename\":\"Product\",\"usItemId\":\"1\",\"name\":\"x\",\"fulfillmentSummary\":[\
       \{\"fulfillment\":\"DRONE\",\"deliveryDate\":null}]}]}]}}}}"
      (\r -> map foMethod (concatMap psFulfillment (srProducts r))
               @?= [UnknownFulfillment "DRONE"])

  , searchCase "an item with no fulfillment block offers nothing"
      "{\"data\":{\"search\":{\"searchResult\":{\"itemStacks\":[{\"itemsV2\":[\
       \{\"__typename\":\"Product\",\"usItemId\":\"1\",\"name\":\"x\"}]}]}}}}"
      (\r -> concatMap psFulfillment (srProducts r) @?= [])
  ]

-- | Walmart answers stock against a particular store whether or not one
-- was ever chosen, so the result records which.
storeTests :: Either String Aeson.Value -> TestTree
storeTests mixedBody = testGroup "Store context"
  [ searchCase "a resolved store is reported"
      "{\"data\":{\"search\":{\"searchResult\":{\"itemStacks\":[]}},\
       \\"contentLayout\":{\"pageMetadata\":{\"location\":\
       \{\"storeId\":\"1234\",\"postalCode\":\"99999\"}}}}}"
      (\r -> fmap scStoreId (srStore r) @?= Just "1234")

  , searchCase "a response without a location claims no store"
      "{\"data\":{\"search\":{\"searchResult\":{\"itemStacks\":[]}}}}"
      (\r -> srStore r @?= Nothing)

  , testCase "the corpus carries no store, having been scrubbed" $
      case mixedBody of
        Left err -> assertFailure err
        Right body -> either assertFailure (\r -> srStore r @?= Nothing)
                             (parseSearchResult body)
  ]

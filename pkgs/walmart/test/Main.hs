{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.List (nub, sort)
import Data.Maybe (isJust, isNothing, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (diffUTCTime)
import Test.QuickCheck
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck (testProperty)

import Corpus
import Walmart.Catalog
import Walmart.Discovery.Parse
import Walmart.Operation
import Walmart.Response
  ( Rejection (..)
  , graphQLRejection
  , parseCart
  , parseCartUpdate
  , parseCancelledCart
  , parseReservedCart
  , parseSearchResult
  , parseStoreSwitchedCart
  , parseSlotSchedule
  , parseStores
  , extractNextData
  , parseProductDetail
  )
import Walmart.Types

main :: IO ()
main = do
  builds <- traverse (\b -> (,) b <$> readCorpus (buildFile b)) realBuilds
  refused <- traverse (\(name, path) -> (,) name <$> readCorpus path) refusals
  chunks <- traverse readCorpus chunkFiles
  searchBody <- Aeson.eitherDecodeFileStrict' searchResponseFile
  mixedBody <- Aeson.eitherDecodeFileStrict' mixedTilesFile
  storesBody <- Aeson.eitherDecodeFileStrict' storesFile
  cartBody <- Aeson.eitherDecodeFileStrict' cartFile
  cartOneLine <- Aeson.eitherDecodeFileStrict' cartOneLineFile
  cartAdded <- Aeson.eitherDecodeFileStrict' cartAddedFile
  cartEmptied <- Aeson.eitherDecodeFileStrict' cartEmptiedFile
  cartReserved <- Aeson.eitherDecodeFileStrict' cartReservedFile
  cartCancelled <- Aeson.eitherDecodeFileStrict' cartCancelledFile
  cartSwitched <- Aeson.eitherDecodeFileStrict' cartStoreSwitchedFile
  pages <- traverse (\(pageName, path) -> (,) pageName <$> readCorpus path) productPages
  slotsBody <- Aeson.eitherDecodeFileStrict' slotsFile
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
    , storeFinderTests storesBody
    , cartTests cartBody
    , cartLineTests cartOneLine cartAdded cartEmptied
    , reservationTests cartReserved cartCancelled cartSwitched
    , productPageTests pages
    , slotTests slotsBody
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
      fmap entryHash (lookupOperation merged (operationName GetOrder)) @?= Just seedHash
      fmap entryHash (lookupOperation merged (operationName Search)) @?= Just freshHash

  , testCase "discovery wins over a seed for the same operation" $ do
      seedHash <- requireHash (T.replicate 64 "a")
      freshHash <- requireHash (T.replicate 64 "b")
      let merged = adoptDiscovered
            (seededCatalog [(operationName Search, freshHash)])
            (seededCatalog [(operationName Search, seedHash)])
      fmap entryHash (lookupOperation merged (operationName Search)) @?= Just freshHash

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
      "{\"errors\":[{\"message\":\"boom\"}]}" (Just (QueryRejected "boom"))

  , rejectionCase "several errors are all reported"
      "{\"errors\":[{\"message\":\"a\"},{\"message\":\"b\"}]}" (Just (QueryRejected "a; b"))

  , rejectionCase "variable validation errors name the variables and spare the catalog"
      "{\"errors\":[{\"message\":\"missing variable `$x`\",\"extensions\":{\"code\":\"VALIDATION_INVALID_TYPE_VARIABLE\"}}]}"
      (Just (VariablesRejected ["missing variable `$x`"]))

  , rejectionCase "a validation error beside an unclassified one is still a query rejection"
      "{\"errors\":[{\"message\":\"v\",\"extensions\":{\"code\":\"VALIDATION_X\"}},{\"message\":\"q\"}]}"
      (Just (QueryRejected "v; q"))

  , rejectionCase "data alongside errors is a partial success, not a rejection"
      "{\"data\":{\"x\":1},\"errors\":[{\"message\":\"boom\"}]}" Nothing

  , rejectionCase "a plain response is not a rejection"
      "{\"data\":{\"x\":1}}" Nothing

  , testCase "the captured search response is not a rejection" $ do
      body <- Aeson.eitherDecodeFileStrict' searchResponseFile
      either assertFailure (\v -> graphQLRejection v @?= Nothing) body
  ]

rejectionCase :: String -> LBS.ByteString -> Maybe Rejection -> TestTree
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
       \{\"__typename\":\"Product\",\"usItemId\":\"1\",\"offerId\":\"o1\",\"name\":\"x\",\"fulfillmentSummary\":[\
       \{\"fulfillment\":\"DELIVERY\",\"deliveryDate\":null},\
       \{\"fulfillment\":\"DELIVERY\",\"deliveryDate\":\"2026-08-24T22:00:00.000Z\"},\
       \{\"fulfillment\":\"DELIVERY\",\"deliveryDate\":\"2026-08-22T22:00:00.000Z\"},\
       \{\"fulfillment\":\"PICKUP\",\"deliveryDate\":\"2026-08-21T10:00:00.000Z\"}]}]}]}}}}"
      (\r -> case srProducts r of
         [p] -> map foMethod (psFulfillment p) @?= [Delivery, Pickup]
         other -> assertFailure ("expected one product, got " <> show (length other)))

  , searchCase "the soonest date wins for a repeated method"
      "{\"data\":{\"search\":{\"searchResult\":{\"itemStacks\":[{\"itemsV2\":[\
       \{\"__typename\":\"Product\",\"usItemId\":\"1\",\"offerId\":\"o1\",\"name\":\"x\",\"fulfillmentSummary\":[\
       \{\"fulfillment\":\"DELIVERY\",\"deliveryDate\":\"2026-08-24T22:00:00.000Z\"},\
       \{\"fulfillment\":\"DELIVERY\",\"deliveryDate\":\"2026-08-22T22:00:00.000Z\"}]}]}]}}}}"
      (\r -> case concatMap psFulfillment (srProducts r) of
         [o] -> fmap show (foEarliest o) @?= Just "2026-08-22 22:00:00 UTC"
         other -> assertFailure ("expected one option, got " <> show (length other)))

  , searchCase "an unfamiliar method is carried, not rejected"
      "{\"data\":{\"search\":{\"searchResult\":{\"itemStacks\":[{\"itemsV2\":[\
       \{\"__typename\":\"Product\",\"usItemId\":\"1\",\"offerId\":\"o1\",\"name\":\"x\",\"fulfillmentSummary\":[\
       \{\"fulfillment\":\"DRONE\",\"deliveryDate\":null}]}]}]}}}}"
      (\r -> map foMethod (concatMap psFulfillment (srProducts r))
               @?= [UnknownFulfillment "DRONE"])

  , searchCase "an item with no fulfillment block offers nothing"
      "{\"data\":{\"search\":{\"searchResult\":{\"itemStacks\":[{\"itemsV2\":[\
       \{\"__typename\":\"Product\",\"usItemId\":\"1\",\"offerId\":\"o1\",\"name\":\"x\"}]}]}}}}"
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

storeFinderTests :: Either String Aeson.Value -> TestTree
storeFinderTests (Left err) = testCase "store corpus decodes" (assertFailure err)
storeFinderTests (Right body) = testGroup "Store finder"
  [ testCase "every node in the capture is a store" $
      either assertFailure (\stores -> length stores @?= 15) (parseStores body)

  , testCase "access types are deduplicated and typed" $
      either assertFailure
        (\stores -> map storeAccessTypes (take 1 stores) @?= [[DeliveryAddress, PickupInStore, PickupCurbside]])
        (parseStores body)

  , testCase "stores arrive nearest first" $
      either assertFailure
        (\stores -> let ds = map storeDistanceMiles stores in ds @?= sort ds)
        (parseStores body)
  ]

cartTests :: Either String Aeson.Value -> TestTree
cartTests (Left err) = testCase "cart corpus decodes" (assertFailure err)
cartTests (Right body) = testGroup "Cart"
  [ testCase "the empty cart reports its store and no lines" $
      either assertFailure
        (\cart -> (cartStoreId cart, cartIntent cart, cartLines cart, cartTotals cart)
                    @?= (StoreId "1234", DeliveryIntent, [], Nothing))
        (parseCart body)
  ]

slotTests :: Either String Aeson.Value -> TestTree
slotTests (Left err) = testCase "slot corpus decodes" (assertFailure err)
slotTests (Right body) = testGroup "Slots"
  [ testCase "three days of slots are read" $
      either assertFailure (\s -> length (ssDays s) @?= 3) (parseSlotSchedule body)

  , testCase "scheduled slots have a two-hour window" $
      either assertFailure
        (\s -> let windows = [ (a, b) | day <- ssDays s, slot <- sdSlots day, Scheduled a b <- [slotTiming slot] ]
               in (not (null windows), nub [ realToFrac (b `diffUTCTime` a) / 3600 | (a, b) <- windows ]) @?= (True, [2 :: Double]))
        (parseSlotSchedule body)

  , testCase "express slots carry their promise in minutes" $
      either assertFailure
        (\s -> length [ m | day <- ssDays s, slot <- sdSlots day, Express m <- [slotTiming slot] ] @?= 2)
        (parseSlotSchedule body)

  , testCase "an unavailable slot has no expiry" $
      either assertFailure
        (\s -> let unavailable = [ slot | day <- ssDays s, slot <- sdSlots day, not (slotAvailable slot) ]
               in (not (null unavailable), all (isNothing . slotExpiry) unavailable) @?= (True, True))
        (parseSlotSchedule body)

  , testCase "an available slot keeps the metadata Walmart wants back" $
      either assertFailure
        (\s -> all (isJust . slotMetadata) [ slot | day <- ssDays s, slot <- sdSlots day, slotAvailable slot ] @?= True)
        (parseSlotSchedule body)

  , testCase "a slot kind this client does not know still lists" $
      case Aeson.eitherDecode "{\"data\":{\"slots\":{\"slotDays\":[{\"day\":\"2026-01-01\",\"eachDaySlots\":[{\"__typename\":\"DroneSlot\",\"id\":\"s\",\"accessPointId\":\"a\",\"available\":true,\"price\":{\"total\":{\"value\":0}}}]}]}}}" of
        Left err -> assertFailure err
        Right v -> either assertFailure
          (\s -> map slotTiming (concatMap sdSlots (ssDays s)) @?= [UnknownSlotKind "DroneSlot"])
          (parseSlotSchedule v)
  ]

cartLineTests :: Either String Aeson.Value -> Either String Aeson.Value -> Either String Aeson.Value -> TestTree
cartLineTests (Left err) _ _ = testCase "one-line cart corpus decodes" (assertFailure err)
cartLineTests _ (Left err) _ = testCase "added cart corpus decodes" (assertFailure err)
cartLineTests _ _ (Left err) = testCase "emptied cart corpus decodes" (assertFailure err)
cartLineTests (Right oneLine) (Right added) (Right emptied) = testGroup "Cart lines"
  [ testCase "a line carries the item, the offer, the quantity and its price in cents" $
      either assertFailure
        (\cart -> map (\l -> (clUsItemId l, clOfferId l, clQuantity l, toInteger (clLinePrice l))) (cartLines cart)
                    @?= [(UsItemId "10450114", OfferId "E262E6B27BDE4ABA86CA2C1DF82ADEF4", 1, 346)])
        (parseCart oneLine)

  , testCase "reading the cart prices it fully" $
      either assertFailure
        (\cart -> fmap (\t -> (toInteger (ctSubtotal t), fmap toInteger (ctEstimatedTotal t), fmap toInteger (ctOrderMinimum t), fmap toInteger (ctBelowMinimumFee t))) (cartTotals cart)
                    @?= Just (346, Just 1045, Just 3500, Just 699))
        (parseCart oneLine)

  , testCase "a mutation answers with identifiers, prices and the subtotal" $
      either assertFailure
        (\r -> (map (\l -> (rlOfferId l, rlQuantity l, toInteger (rlLinePrice l))) (crLines r), fmap toInteger (crSubtotal r))
                 @?= ([(OfferId "E262E6B27BDE4ABA86CA2C1DF82ADEF4", 1, 346)], Just 346))
        (parseCartUpdate added)

  , testCase "removing the last line leaves an unpriced cart" $
      either assertFailure
        (\r -> (crLines r, crSubtotal r) @?= ([], Nothing))
        (parseCartUpdate emptied)
  ]

reservationTests :: Either String Aeson.Value -> Either String Aeson.Value -> Either String Aeson.Value -> TestTree
reservationTests (Left err) _ _ = testCase "reserved cart corpus decodes" (assertFailure err)
reservationTests _ (Left err) _ = testCase "cancelled cart corpus decodes" (assertFailure err)
reservationTests _ _ (Left err) = testCase "store-switched cart corpus decodes" (assertFailure err)
reservationTests (Right reserved) (Right cancelled) (Right switched) = testGroup "Reservations and store"
  [ testCase "a reservation names its slot window, fee and deadline" $
      either assertFailure
        (\cart -> fmap (\r -> (reservationId r, rsTiming (reservationSlot r), toInteger (rsFee (reservationSlot r)), reservationExpiry r)) (cartReservation cart)
                    @?= Just ( ReservationId "res-0"
                             , Scheduled (read "2026-08-23 10:00:00 UTC") (read "2026-08-23 12:00:00 UTC")
                             , 0
                             , read "2026-08-22 23:35:34 UTC" ))
        (parseReservedCart reserved)

  , testCase "reserving marks the store as chosen" $
      either assertFailure (\cart -> cartStoreChoice cart @?= ChosenStore) (parseReservedCart reserved)

  , testCase "cancelling leaves no reservation and an unstated store choice" $
      either assertFailure
        (\cart -> (cartReservation cart, cartStoreChoice cart) @?= (Nothing, UnstatedStore))
        (parseCancelledCart cancelled)

  , testCase "switching store reports the new store, inferred, with no reservation" $
      either assertFailure
        (\cart -> (cartStoreId cart, cartStoreChoice cart, cartReservation cart) @?= (StoreId "4321", InferredStore, Nothing))
        (parseStoreSwitchedCart switched)
  ]

productPageTests :: [(String, Text)] -> TestTree
productPageTests pages = testGroup "Product page"
  [ testCase "every captured page embeds product data" $
      mapM_ (\(pageName, html) -> assertBool (pageName <> " has no __NEXT_DATA__") (isJust (extractNextData html))) pages

  , testCase "a page without the data script yields nothing" $
      extractNextData "<html><script>1</script></html>" @?= Nothing

  , testCase "the milk page states UPC, ingredients and net content" $
      either assertFailure
        (\p -> (pdUpc p, pdIngredients p, pdNetContent p, pdBrand p)
                 @?= (Just (Upc "078742351865"), Just "Milk, Vitamin D3. Contains Milk.", Just "1 GAL (378 L)", Just "Great Value"))
        (detailOf "milk")

  , testCase "a weight-sold item states its net content as a weight" $
      either assertFailure
        (\p -> (pdUpc p, pdNetContent p, pdPricePerUnit p) @?= (Just (Upc "078742269573"), Just "1 lb", Just "$8.47/lb"))
        (detailOf "beef")

  , testCase "the category path is the department chain" $
      either assertFailure
        (\p -> pdCategoryPath p @?= ["Food", "Dairy & Eggs", "Milk", "Dairy Milk", "Whole Milk"])
        (detailOf "milk")

  , testCase "the specification table is carried whole" $
      either assertFailure
        (\p -> length (pdSpecifications p) @?= 13)
        (detailOf "milk")
  ]
  where
    detailOf pageName = case lookup pageName pages of
      Nothing -> Left ("no page labelled " <> pageName)
      Just html -> case extractNextData html of
        Nothing -> Left "no data script"
        Just payload -> Aeson.eitherDecodeStrict (TE.encodeUtf8 payload) >>= parseProductDetail

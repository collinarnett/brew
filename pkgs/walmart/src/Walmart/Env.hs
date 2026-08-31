{-# LANGUAGE OverloadedStrings #-}

-- | The API surface, and the catalog upkeep that keeps it working.
--
-- Walmart rotates persisted query hashes with every frontend release
-- and refuses a retired one. A request that meets such a refusal
-- refreshes the catalog and runs again, so rotation costs a repeat
-- request rather than a release of this client. Each refresh is
-- recorded as a notice, which callers drain with 'takeNotices'.
module Walmart.Env
  ( Env
  , newEnv
  , takeNotices
  , refreshCatalog
  , effectiveCatalog
  , getOrders
  , getOrderDetails
  , searchProducts
  , findStores
  , getCart
  , getSlots
  , updateCart
  , reserveSlot
  , cancelReservation
  , setDeliveryStore
  , probe
  ) where

import Data.Aeson qualified as Aeson
import Control.Concurrent (threadDelay)
import Control.Concurrent.MVar (MVar, modifyMVar_, newMVar)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime, diffUTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import Network.HTTP.Client (CookieJar, Manager, newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)

import Walmart.Catalog
  ( Catalog
  , adoptDiscovered
  , catalogSize
  , loadCatalog
  , renderCatalogError
  , saveCatalog
  )
import Walmart.Discovery (discover, renderDiscoveryError)
import Walmart.Internal.HTTP (resolve, walmartRequest)
import Walmart.Response
  ( Rejection (..)
  , graphQLRejection
  , parseCart
  , parseCartUpdate
  , parseCancelledCart
  , parseOrderSummaries
  , parseReservedCart
  , parseStoreSwitchedCart
  , parseSearchResult
  , parseSlotSchedule
  , parseStores
  , parseWalmartOrder
  )
import Walmart.Operation (Route (..), Target (..), routeTarget)
import Walmart.Types

data Env = Env
  { envManager     :: Manager
  , envCookieJar   :: CookieJar
  , envCatalogPath :: FilePath
  , envCatalog     :: IORef Catalog
  , envSeeds       :: Catalog
  , envNotices     :: IORef [Text]
    -- | When the last request went out, so the next one can wait its
    -- turn. Walmart's bot protection is triggered by bursts, and one
    -- trip blocks every gateway for half an hour.
  , envLastRequest :: MVar (Maybe UTCTime)
  }

-- | The least time between two requests to Walmart.
requestSpacing :: Double
requestSpacing = 1

-- | Block until 'requestSpacing' has passed since the previous request.
awaitTurn :: Env -> IO ()
awaitTurn env = modifyMVar_ (envLastRequest env) $ \previous -> do
  now <- getCurrentTime
  let elapsed = maybe requestSpacing (realToFrac . diffUTCTime now) previous
      wait = requestSpacing - elapsed
  if wait > 0 then threadDelay (round (wait * 1e6)) else pure ()
  Just <$> getCurrentTime

-- | Build an environment around a browser session, the catalog file the
-- program keeps discovered hashes in, and the hashes configuration
-- supplies for operations that never appear in a frontend bundle.
newEnv :: CookieJar -> FilePath -> Catalog -> IO (Either WalmartError Env)
newEnv cookies catalogPath seeds = do
  loaded <- loadCatalog catalogPath
  case loaded of
    Left err -> pure (Left (WalmartDiscoveryFailed (renderCatalogError err)))
    Right catalog -> do
      mgr <- newManager tlsManagerSettings
      ref <- newIORef catalog
      notices <- newIORef []
      lastRequest <- newMVar Nothing
      pure $ Right Env
        { envManager     = mgr
        , envCookieJar   = cookies
        , envCatalogPath = catalogPath
        , envCatalog     = ref
        , envSeeds       = seeds
        , envNotices     = notices
        , envLastRequest = lastRequest
        }

-- | Take and clear everything worth telling the caller about.
takeNotices :: Env -> IO [Text]
takeNotices env = atomicModifyIORef' (envNotices env) (\ns -> ([], reverse ns))

note :: Env -> Text -> IO ()
note env msg = atomicModifyIORef' (envNotices env) (\ns -> (msg : ns, ()))

-- | Scan Walmart's current frontend build and fold what it finds over
-- the catalog on disk.
refreshCatalog :: Env -> IO (Either WalmartError ())
refreshCatalog env = do
  found <- discover (envManager env)
  case found of
    Left err -> pure (Left (WalmartDiscoveryFailed (renderDiscoveryError err)))
    Right discovered -> do
      known <- readIORef (envCatalog env)
      let merged = adoptDiscovered discovered known
      saveCatalog (envCatalogPath env) merged
      _ <- atomicModifyIORef' (envCatalog env) (\_ -> (merged, ()))
      note env $
        "Refreshed the endpoint catalog: "
        <> T.pack (show (catalogSize discovered)) <> " operations discovered, "
        <> T.pack (show (catalogSize merged)) <> " now known."
      pure (Right ())

-- | What resolution sees: discovered hashes over configured ones.
effectiveCatalog :: Env -> IO Catalog
effectiveCatalog env = do
  discovered <- readIORef (envCatalog env)
  pure (adoptDiscovered discovered (envSeeds env))

-- | How Walmart answered, once the difference between "this hash is no
-- good" and everything else has been decided.
data Attempt
  = Rejected BodyPreview
  | Settled (Either WalmartError Aeson.Value)

-- | Walmart refuses a hash it will not serve in two ways: HTTP 400 for
-- one it cannot parse, and HTTP 200 carrying a GraphQL errors body for
-- one it does not recognise. Both mean the catalog is out of date.
classify :: Either WalmartError Aeson.Value -> Attempt
classify (Left (WalmartBadRequest preview)) = Rejected preview
classify outcome@(Right body) = case graphQLRejection body of
  Just (QueryRejected messages)     -> Rejected (BodyPreview messages)
  Just (VariablesRejected messages) -> Settled (Left (WalmartInvalidVariables messages))
  Nothing                           -> Settled outcome
classify outcome = Settled outcome

-- | Run a route, refreshing the catalog if the hash is missing or
-- Walmart has retired it. Exactly one refresh is attempted per call.
runRoute :: Env -> Route -> Aeson.Value -> IO (Either WalmartError Aeson.Value)
runRoute env route variables = attempt False
  where
    target = routeTarget route
    opName = targetName target

    attempt refreshedAlready = do
      catalog <- effectiveCatalog env
      case resolve catalog target of
        Left (WalmartOperationUnresolved name)
          | refreshedAlready -> pure (Left (WalmartOperationUnresolved name))
          | otherwise        -> refreshAndRetry
        Left err -> pure (Left err)
        Right endpoint -> do
          awaitTurn env
          result <- walmartRequest (envManager env) (envCookieJar env) endpoint variables
          case classify result of
            Settled outcome -> pure outcome
            Rejected preview
              | refreshedAlready -> pure (Left (WalmartStaleAfterRefresh opName preview))
              | otherwise        -> refreshAndRetry

    refreshAndRetry = do
      refreshed <- refreshCatalog env
      case refreshed of
        Left err -> pure (Left err)
        Right () -> attempt True

parsed
  :: Text
  -> (Aeson.Value -> Either String a)
  -> Either WalmartError Aeson.Value
  -> Either WalmartError a
parsed _ _ (Left err) = Left err
parsed label parser (Right body) = case parser body of
  Left err  -> Left (WalmartParseError label err)
  Right val -> Right val

getOrders :: Env -> Maybe UTCTime -> Int -> IO (Either WalmartError [OrderSummary])
getOrders env mSince limit = do
  let sinceTs = fmap (round . utcTimeToPOSIXSeconds) mSince :: Maybe Integer
      variables = Aeson.object
        [ "input" Aeson..= Aeson.object
            [ "cursor"       Aeson..= ("" :: Text)
            , "search"       Aeson..= ("" :: Text)
            , "filterIds"    Aeson..= ([] :: [Text])
            , "limit"        Aeson..= limit
            , "type"         Aeson..= Aeson.Null
            , "minTimestamp" Aeson..= sinceTs
            , "maxTimestamp" Aeson..= Aeson.Null
            ]
        , "platform" Aeson..= ("WEB" :: Text)
        ]
  parsed "PurchaseHistoryV2" parseOrderSummaries
    <$> runRoute env PurchaseHistoryRoute variables

getOrderDetails :: Env -> OrderId -> OrderChannel -> IO (Either WalmartError WalmartOrder)
getOrderDetails env orderId channel = do
  let inStore = case channel of
        InStore -> True
        Online  -> False
      variables = Aeson.object
        [ "orderId"              Aeson..= unOrderId orderId
        , "orderIsInStore"       Aeson..= inStore
        , "clickThroughGroupId"  Aeson..= ("0" :: Text)
        , "enableIsWcpOrder"     Aeson..= False
        , "enabledFeatures"      Aeson..= (["csat-northstar-v1", "tips", "delivery-fees"] :: [Text])
        , "enableSignOnDelivery" Aeson..= True
        , "includeTipDetails"    Aeson..= True
        , "includeFeesDetails"   Aeson..= True
        ]
  parsed "getOrder" parseWalmartOrder <$> runRoute env GetOrderRoute variables

searchProducts :: Env -> SearchQuery -> IO (Either WalmartError SearchResult)
searchProducts env query =
  parsed "Search" parseSearchResult <$> runRoute env SearchRoute (searchVariables query)

-- | Walmart's search gateway rejects a variables object that omits the
-- flags its resolvers branch on, so every one it expects is stated even
-- where the value is the uninteresting one.
searchVariables :: SearchQuery -> Aeson.Value
searchVariables query = Aeson.object
  [ "id"                    Aeson..= ("" :: Text)
  , "dealsId"               Aeson..= ("" :: Text)
  , "query"                 Aeson..= sqTerm query
  , "page"                  Aeson..= sqPage query
  , "prg"                   Aeson..= ("desktop" :: Text)
  , "catId"                 Aeson..= maybe "" unCategoryId (sqCategoryId query)
  , "facet"                 Aeson..= ("" :: Text)
  , "sort"                  Aeson..= ("best_match" :: Text)
  , "rawFacet"              Aeson..= ("" :: Text)
  , "seoPath"               Aeson..= ("" :: Text)
  , "ps"                    Aeson..= sqLimit query
  , "limit"                 Aeson..= sqLimit query
  , "ptss"                  Aeson..= ("" :: Text)
  , "trsp"                  Aeson..= ("" :: Text)
  , "beShelfId"             Aeson..= ("" :: Text)
  , "recall_set"            Aeson..= ("" :: Text)
  , "module_search"         Aeson..= ("" :: Text)
  , "min_price"             Aeson..= ("" :: Text)
  , "max_price"             Aeson..= ("" :: Text)
  , "storeSlotBooked"       Aeson..= ("" :: Text)
  , "additionalQueryParams" Aeson..= Aeson.object
      [ "hidden_facet"             Aeson..= Aeson.Null
      , "translation"              Aeson..= Aeson.Null
      , "isMoreOptionsTileEnabled" Aeson..= True
      ]
  , "searchArgs"            Aeson..= Aeson.object
      [ "query"  Aeson..= sqTerm query
      , "cat_id" Aeson..= maybe "" unCategoryId (sqCategoryId query)
      , "prg"    Aeson..= ("desktop" :: Text)
      , "facet"  Aeson..= ("" :: Text)
      ]
  , "fitmentFieldParams"    Aeson..= Aeson.object
      [ "powerSportEnabled"         Aeson..= True
      , "dynamicFitmentEnabled"     Aeson..= True
      , "extendedAttributesEnabled" Aeson..= False
      ]
  , "enableFashionTopNav"   Aeson..= False
  , "enableRelatedSearches" Aeson..= True
  , "enablePortableFacets"  Aeson..= True
  , "enableFacetCount"      Aeson..= True
  , "fetchMarquee"          Aeson..= False
  , "fetchSkyline"          Aeson..= False
  , "fetchGallery"          Aeson..= False
  , "fetchSbaTop"           Aeson..= False
  , "fetchDac"              Aeson..= False
  , "fetchDataV1"           Aeson..= False
  , "fungibilityEnabled"    Aeson..= False
  , "tenant"                Aeson..= ("WM_GLASS" :: Text)
  , "enableFlattenedFitment" Aeson..= False
  , "enableMultiSave"       Aeson..= False
  , "enableSellerType"      Aeson..= False
  , "enableAdditionalSearchDepartmentAnalytics" Aeson..= False
  , "pageType"              Aeson..= ("SearchPage" :: Text)
  ]

-- | Run any catalogued operation with hand-built variables and return
-- the raw response. This is how a gateway's expectations are learned
-- before an operation is modelled: the gateway answers a wrong
-- variables object by naming what it wanted.
probe :: Env -> Target -> Aeson.Value -> IO (Either WalmartError Aeson.Value)
probe env target = runRoute env (ProbeRoute target)

findStores :: Env -> StoreSearch -> IO (Either WalmartError [Store])
findStores env search = do
  let variables = Aeson.object
        [ "input" Aeson..= Aeson.object
            [ "postalCode"  Aeson..= unPostalCode (ssPostalCode search)
            , "nodeTypes"   Aeson..= (["STORE"] :: [Text])
            , "accessTypes" Aeson..= (["PICKUP_INSTORE", "PICKUP_CURBSIDE", "DELIVERY_ADDRESS"] :: [Text])
            , "radius"      Aeson..= ssRadiusMiles search
            ]
        ]
  parsed "storeFinderNearbyNodesQuery" parseStores <$> runRoute env FindStoresRoute variables

getCart :: Env -> IO (Either WalmartError Cart)
getCart env = do
  let variables = Aeson.object
        [ "cartInput" Aeson..= Aeson.object
            [ "forceRefresh"           Aeson..= False
            , "enableLiquorBox"        Aeson..= False
            , "enableCartSplitClarity" Aeson..= False
            , "features"               Aeson..= ([] :: [Text])
            ]
        ]
  parsed "getCart" parseCart <$> runRoute env GetCartRoute variables

-- | The slots Walmart offers the session's cart. The gateway validates
-- every flag it branches on, so each one is stated.
getSlots :: Env -> FulfillmentIntent -> IO (Either WalmartError SlotSchedule)
getSlots env intent = do
  let variables = Aeson.object
        [ "cartId"                                 Aeson..= ("" :: Text)
        , "fulfillmentOption"                      Aeson..= intentLabel intent
        , "isGuest"                                Aeson..= False
        , "isExpressSla"                           Aeson..= False
        , "maxAvailableSlotsCount"                 Aeson..= (10 :: Int)
        , "enableWalmartPlusFreeDiscountedExpress" Aeson..= False
        , "enableDeliveryAddressFromSlotData"      Aeson..= False
        ]
  parsed "getSlots" parseSlotSchedule <$> runRoute env GetSlotsRoute variables

-- | Set line quantities in the cart and return what Walmart left in it.
-- A quantity of zero removes the line.
updateCart :: Env -> CartId -> [CartUpdate] -> IO (Either WalmartError CartReceipt)
updateCart env cid updates = do
  let item u = Aeson.object
        [ "offerId"  Aeson..= unOfferId (cuOfferId u)
        , "quantity" Aeson..= cuQuantity u
        ]
      variables = Aeson.object
        [ "input" Aeson..= Aeson.object
            [ "items"                  Aeson..= map item updates
            , "cartId"                 Aeson..= unCartId cid
            , "enableLiquorBox"        Aeson..= False
            , "enableCartSplitClarity" Aeson..= False
            , "features"               Aeson..= ([] :: [Text])
            ]
        ]
  parsed "updateItems" parseCartUpdate <$> runRoute env UpdateItemsRoute variables

-- | Hold a slot for the cart. The metadata is the blob a listed slot
-- carried; Walmart reads the slot, store and fulfillment from it.
reserveSlot :: Env -> CartId -> SlotMetadata -> IO (Either WalmartError Reservation)
reserveSlot env cid metadata = do
  let variables = Aeson.object
        [ "cartId"          Aeson..= unCartId cid
        , "slotMetadata"    Aeson..= unSlotMetadata metadata
        , "enableLiquorBox" Aeson..= False
        , "features"        Aeson..= ([] :: [Text])
        ]
  answer <- parsed "reserveSlotMutation" parseReservedCart <$> runRoute env ReserveSlotRoute variables
  pure $ case answer of
    Left err -> Left err
    Right cart -> case cartReservation cart of
      Just reservation -> Right reservation
      Nothing -> Left (WalmartParseError "reserveSlotMutation" "Walmart answered without a reservation")

-- | Release a held slot and return the cart as it stands.
cancelReservation :: Env -> ReservationId -> IO (Either WalmartError Cart)
cancelReservation env rid = do
  let variables = Aeson.object
        [ "input" Aeson..= Aeson.object [ "reservationId" Aeson..= unReservationId rid ] ]
  parsed "cancelReservation" parseCancelledCart <$> runRoute env CancelReservationRoute variables

-- | Point the session's cart, and with it every stock answer, at a
-- store. Walmart drops any held slot when the store changes.
setDeliveryStore :: Env -> CartId -> StoreId -> IO (Either WalmartError Cart)
setDeliveryStore env cid sid = do
  let variables = Aeson.object
        [ "input" Aeson..= Aeson.object
            [ "cartId"  Aeson..= unCartId cid
            , "storeId" Aeson..= storeNumber
            ]
        , "includePartialFulfillmentSwitching" Aeson..= False
        ]
      storeNumber = case reads (T.unpack (unStoreId sid)) :: [(Int, String)] of
        [(n, "")] -> Aeson.toJSON n
        _notNumeric -> Aeson.toJSON (unStoreId sid)
  parsed "setDeliveryStore" parseStoreSwitchedCart <$> runRoute env SetDeliveryStoreRoute variables

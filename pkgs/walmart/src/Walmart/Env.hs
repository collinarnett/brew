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
  ) where

import Data.Aeson qualified as Aeson
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
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
  ( graphQLRejection
  , parseOrderSummaries
  , parseSearchResult
  , parseWalmartOrder
  )
import Walmart.Operation (Route (..), operationName, routeOperation)
import Walmart.Types

data Env = Env
  { envManager     :: Manager
  , envCookieJar   :: CookieJar
  , envCatalogPath :: FilePath
  , envCatalog     :: IORef Catalog
  , envSeeds       :: Catalog
  , envNotices     :: IORef [Text]
  }

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
      pure $ Right Env
        { envManager     = mgr
        , envCookieJar   = cookies
        , envCatalogPath = catalogPath
        , envCatalog     = ref
        , envSeeds       = seeds
        , envNotices     = notices
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
  Just messages -> Rejected (BodyPreview messages)
  Nothing       -> Settled outcome
classify outcome = Settled outcome

-- | Run a route, refreshing the catalog if the hash is missing or
-- Walmart has retired it. Exactly one refresh is attempted per call.
runRoute :: Env -> Route -> Aeson.Value -> IO (Either WalmartError Aeson.Value)
runRoute env route variables = attempt False
  where
    opName = operationName (routeOperation route)

    attempt refreshedAlready = do
      catalog <- effectiveCatalog env
      case resolve catalog route of
        Left (WalmartOperationUnresolved name)
          | refreshedAlready -> pure (Left (WalmartOperationUnresolved name))
          | otherwise        -> refreshAndRetry
        Left err -> pure (Left err)
        Right endpoint -> do
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

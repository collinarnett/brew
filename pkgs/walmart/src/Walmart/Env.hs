{-# LANGUAGE OverloadedStrings #-}

module Walmart.Env
  ( Env
  , newEnv
  , getOrders
  , getOrder
  ) where

import Data.Aeson qualified as Aeson
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import Network.HTTP.Client (CookieJar, Manager, newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)

import Walmart.Internal.Endpoints qualified as Endpoints
import Walmart.Internal.HTTP (walmartRequest)
import Walmart.Internal.JSON (parseOrderSummaries, parseWalmartOrder)
import Walmart.Types

data Env = Env
  { envManager   :: Manager
  , envCookieJar :: CookieJar
  }

newEnv :: CookieJar -> IO Env
newEnv cookies = do
  mgr <- newManager tlsManagerSettings
  pure Env { envManager = mgr, envCookieJar = cookies }

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
  result <- walmartRequest (envManager env) (envCookieJar env)
    Endpoints.purchaseHistoryUrl "PurchaseHistoryV2" variables
  pure $ case result of
    Left err   -> Left err
    Right body -> case parseOrderSummaries body of
      Left err        -> Left (WalmartParseError "PurchaseHistoryV2" err)
      Right summaries -> Right summaries

getOrder :: Env -> OrderSummary -> IO (Either WalmartError WalmartOrder)
getOrder env summary = do
  let variables = Aeson.object
        [ "orderId"              Aeson..= unOrderId (osOrderId summary)
        , "orderIsInStore"       Aeson..= osIsInStore summary
        , "clickThroughGroupId"  Aeson..= ("0" :: Text)
        , "enableIsWcpOrder"     Aeson..= False
        , "enabledFeatures"      Aeson..= (["csat-northstar-v1", "tips", "delivery-fees"] :: [Text])
        , "enableSignOnDelivery" Aeson..= True
        , "includeTipDetails"    Aeson..= True
        , "includeFeesDetails"   Aeson..= True
        ]
  result <- walmartRequest (envManager env) (envCookieJar env)
    Endpoints.getOrderUrl "getOrder" variables
  pure $ case result of
    Left err   -> Left err
    Right body -> case parseWalmartOrder body of
      Left err    -> Left (WalmartParseError "getOrder" err)
      Right order -> Right order

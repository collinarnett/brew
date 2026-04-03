{-# LANGUAGE OverloadedStrings #-}

-- | Walmart GraphQL API client.
module WalmartGrocy.Walmart
  ( walmartGetHistory
  , walmartGetOrder
  ) where

import Data.Aeson qualified as Aeson
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.CaseInsensitive qualified as CI
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (UTCTime)
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import Network.HTTP.Client
import Network.HTTP.Types.Header (Header)
import Network.HTTP.Types.Status (statusCode)
import System.IO (hPutStrLn, stderr)

import WalmartGrocy.JSON (parseOrderSummaries, parseWalmartOrder)
import WalmartGrocy.Types

-- | Headers required by Walmart's GraphQL API.
mkHeaders :: Text -> [Header]
mkHeaders opName = map (\(k, v) -> (CI.mk (TE.encodeUtf8 k), TE.encodeUtf8 v))
  [ ("accept",                  "application/json")
  , ("content-type",            "application/json")
  , ("user-agent",              "Mozilla/5.0 (X11; Linux x86_64) Chrome/131.0.0.0")
  , ("x-o-platform",            "rweb")
  , ("x-o-bu",                  "WALMART-US")
  , ("x-o-mart",                "B2C")
  , ("x-o-segment",             "oaoh")
  , ("wm_mp",                   "true")
  , ("dnt",                     "1")
  , ("x-o-platform-version",    "usweb-1.221.0")
  , ("x-apollo-operation-name", opName)
  , ("x-o-gql-query",           "query " <> opName)
  ]

-- | Fetch order summaries from PurchaseHistoryV2.
walmartGetHistory
  :: Manager
  -> CookieJar
  -> Map.Map Text EndpointUrl
  -> Maybe UTCTime
  -> Int
  -> IO [OrderSummary]
walmartGetHistory mgr cookies endpoints mSince limit = do
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
      EndpointUrl url = endpoints Map.! "PurchaseHistoryV2"
  body <- walmartRequest mgr cookies url "PurchaseHistoryV2" variables
  case parseOrderSummaries body of
    Left err -> fail ("Failed to parse purchase history: " <> err)
    Right summaries -> pure summaries

-- | Fetch full order details with per-item prices.
walmartGetOrder
  :: Manager
  -> CookieJar
  -> Map.Map Text EndpointUrl
  -> OrderSummary
  -> IO WalmartOrder
walmartGetOrder mgr cookies endpoints summary = do
  let EndpointUrl url = endpoints Map.! "getOrder"
      variables = Aeson.object
        [ "orderId"              Aeson..= unOrderId (osOrderId summary)
        , "orderIsInStore"       Aeson..= osIsInStore summary
        , "clickThroughGroupId"  Aeson..= ("0" :: Text)
        , "enableIsWcpOrder"     Aeson..= False
        , "enabledFeatures"      Aeson..= (["csat-northstar-v1", "tips", "delivery-fees"] :: [Text])
        , "enableSignOnDelivery" Aeson..= True
        , "includeTipDetails"    Aeson..= True
        , "includeFeesDetails"   Aeson..= True
        ]
  body <- walmartRequest mgr cookies url "getOrder" variables
  case parseWalmartOrder body of
    Left err -> fail ("Failed to parse order "
      <> T.unpack (unOrderId (osOrderId summary)) <> ": " <> err)
    Right order -> pure order

-- | Make an authenticated GET request to Walmart's GraphQL API.
-- | Render a CookieJar as a raw Cookie header value.
cookieHeader :: CookieJar -> BS.ByteString
cookieHeader jar =
  let cookies = destroyCookieJar jar
      pairs = map (\c -> cookie_name c <> "=" <> cookie_value c) cookies
  in BS.intercalate "; " pairs

walmartRequest
  :: Manager -> CookieJar -> Text -> Text -> Aeson.Value -> IO Aeson.Value
walmartRequest mgr cookies url opName variables = do
  initReq <- parseRequest (T.unpack url)
  let varsBS = LBS.toStrict (Aeson.encode variables)
      req0 = setQueryString [("variables", Just varsBS)] initReq
  let cookieBS = cookieHeader cookies
      req = req0
        { method = "GET"
        , requestHeaders =
            ("Cookie", cookieBS) : mkHeaders opName
        }
  hPutStrLn stderr ("GET " <> T.unpack opName <> " (" <> show (BS.length cookieBS) <> " bytes of cookies)")
  resp <- httpLbs req mgr
  let code = statusCode (responseStatus resp)
      bodyPreview = take 200 (show (responseBody resp))
  hPutStrLn stderr ("  -> HTTP " <> show code <> " (" <> show (LBS.length (responseBody resp)) <> " bytes)")
  case code of
    200 -> case Aeson.eitherDecode (responseBody resp) of
      Left err  -> fail ("JSON decode failed: " <> err <> "\nResponse: " <> bodyPreview)
      Right val -> pure val
    400 -> fail "Walmart returned 400 — hash may have rotated. Run with --invalidate-cache."
    429 -> fail "Rate limited — log into walmart.com in Firefox to refresh cookies."
    403 -> fail "Access denied (403) — cookies expired. Log into walmart.com."
    418 -> fail "Access denied (418) — cookies expired. Log into walmart.com."
    _   -> fail ("Walmart API returned HTTP " <> show code)

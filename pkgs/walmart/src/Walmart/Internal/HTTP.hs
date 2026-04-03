{-# LANGUAGE OverloadedStrings #-}

module Walmart.Internal.HTTP
  ( walmartRequest
  ) where

import Data.Aeson qualified as Aeson
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.CaseInsensitive qualified as CI
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.HTTP.Client
import Network.HTTP.Types.Header (Header)
import Network.HTTP.Types.Status (statusCode)

import Walmart.Types

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

cookieHeader :: CookieJar -> BS.ByteString
cookieHeader jar =
  let cs = destroyCookieJar jar
      pairs = map (\c -> cookie_name c <> "=" <> cookie_value c) cs
  in BS.intercalate "; " pairs

walmartRequest
  :: Manager -> CookieJar -> Text -> Text -> Aeson.Value
  -> IO (Either WalmartError Aeson.Value)
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
  resp <- httpLbs req mgr
  let code = statusCode (responseStatus resp)
      bodyPreview = take 200 (show (responseBody resp))
  case code of
    200 -> case Aeson.eitherDecode (responseBody resp) of
      Left err  -> pure (Left (WalmartJsonDecodeError err bodyPreview))
      Right val -> pure (Right val)
    400 -> pure (Left WalmartHashRotated)
    429 -> pure (Left WalmartRateLimited)
    403 -> pure (Left (WalmartAccessDenied 403))
    418 -> pure (Left (WalmartAccessDenied 418))
    _   -> pure (Left (WalmartHttpError code))

{-# LANGUAGE OverloadedStrings #-}

-- | Talking to Walmart's orchestra gateways.
--
-- An 'Endpoint' cannot be written down: 'resolve' is the only way to
-- obtain one, and it needs a catalogued hash. A persisted query id
-- therefore never enters this library as source.
module Walmart.Internal.HTTP
  ( Endpoint
  , resolve
  , walmartRequest
  ) where

import Control.Exception (displayException, try)
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

import Walmart.Catalog (Catalog, entryHash, lookupOperation)
import Walmart.Operation
  ( Operation
  , Route
  , operationName
  , routeOperation
  , routeUrl
  )
import Walmart.Types

-- | A request target with a hash the catalog vouches for.
data Endpoint = Endpoint
  { endpointUrl       :: Text
  , endpointOperation :: Operation
  }

resolve :: Catalog -> Route -> Either WalmartError Endpoint
resolve catalog route =
  let op = routeOperation route
  in case lookupOperation catalog op of
    Nothing -> Left (WalmartOperationUnresolved (operationName op))
    Just entry -> Right Endpoint
      { endpointUrl       = routeUrl (entryHash entry) route
      , endpointOperation = op
      }

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

-- | Firefox cookies must go out as a raw Cookie header; http-client's
-- cookieJar support drops them because of @.walmart.com@ domain filtering.
cookieHeader :: CookieJar -> BS.ByteString
cookieHeader jar =
  let cs = destroyCookieJar jar
      pairs = map (\c -> cookie_name c <> "=" <> cookie_value c) cs
  in BS.intercalate "; " pairs

walmartRequest
  :: Manager -> CookieJar -> Endpoint -> Aeson.Value
  -> IO (Either WalmartError Aeson.Value)
walmartRequest mgr cookies endpoint variables = do
  attempt <- try $ do
    initReq <- parseRequest (T.unpack (endpointUrl endpoint))
    let varsBS = LBS.toStrict (Aeson.encode variables)
        req0 = setQueryString [("variables", Just varsBS)] initReq
        cookieBS = cookieHeader cookies
        opName = unOperationName (operationName (endpointOperation endpoint))
        req = req0
          { method = "GET"
          , requestHeaders = ("Cookie", cookieBS) : mkHeaders opName
          }
    httpLbs req mgr
  pure $ case attempt of
    Left err -> Left (WalmartNetworkError (T.pack (displayException (err :: HttpException))))
    Right resp ->
      let code = statusCode (responseStatus resp)
          preview = T.take 8000 (TE.decodeUtf8Lenient (LBS.toStrict (responseBody resp)))
      in case code of
        200 -> case Aeson.eitherDecode (responseBody resp) of
          Left err  -> Left (WalmartJsonDecodeError err (BodyPreview preview))
          Right val -> Right val
        400 -> Left (WalmartBadRequest (BodyPreview preview))
        429 -> Left WalmartRateLimited
        403 -> Left WalmartAccessDenied
        418 -> Left WalmartAccessDenied
        _   -> Left (WalmartHttpError code (BodyPreview preview))

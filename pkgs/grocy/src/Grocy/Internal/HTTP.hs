{-# LANGUAGE OverloadedStrings #-}

module Grocy.Internal.HTTP
  ( grocyGet
  , grocyPost
  ) where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.HTTP.Client
import Network.HTTP.Types.Status (statusCode)

import Grocy.Types

grocyGet :: Env -> Text -> IO (Either GrocyError LBS.ByteString)
grocyGet env path = do
  let url = T.unpack (envBaseUrl env <> path)
  req <- parseRequest url
  let req' = req
        { method = "GET"
        , requestHeaders =
            [ ("GROCY-API-KEY", TE.encodeUtf8 (envApiKey env))
            , ("Accept", "application/json")
            ]
        }
  resp <- httpLbs req' (envManager env)
  let code = statusCode (responseStatus resp)
  if code == 200
    then pure (Right (responseBody resp))
    else pure (Left (GrocyHttpError path code))

grocyPost :: Env -> Text -> Aeson.Value -> IO LBS.ByteString
grocyPost env path payload = do
  let url = T.unpack (envBaseUrl env <> path)
  req <- parseRequest url
  let req' = req
        { method = "POST"
        , requestHeaders =
            [ ("GROCY-API-KEY", TE.encodeUtf8 (envApiKey env))
            , ("Content-Type", "application/json")
            , ("Accept", "application/json")
            ]
        , requestBody = RequestBodyLBS (Aeson.encode payload)
        }
  resp <- httpLbs req' (envManager env)
  pure (responseBody resp)

{-# LANGUAGE OverloadedStrings #-}

-- | Product pages through a browser.
--
-- Walmart withholds product pages from plain HTTP clients, and the
-- item-detail gateway sits behind a bot-detection challenge no stored
-- cookie satisfies. A browser that runs the page's scripts is served
-- the real document, and the document embeds the product data the
-- page was rendered from. No session is involved: product pages are
-- public.
module Walmart.Render
  ( Renderer (..)
  , getProduct
  ) where

import Data.Aeson qualified as Aeson
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Encoding.Error (lenientDecode)
import Data.ByteString.Lazy qualified as LBS
import System.Exit (ExitCode (..))
import System.Process.ByteString.Lazy (readProcessWithExitCode)

import Walmart.Response (extractNextData, parseProductDetail)
import Walmart.Types

-- | The browser that renders pages: a lightpanda executable.
newtype Renderer = Renderer { rendererExecutable :: FilePath }
  deriving stock (Show, Eq)

productUrl :: UsItemId -> Text
productUrl item = "https://www.walmart.com/ip/" <> unUsItemId item

getProduct :: Renderer -> UsItemId -> IO (Either WalmartError ProductDetail)
getProduct renderer item = do
  (code, out, err) <- readProcessWithExitCode
    (rendererExecutable renderer)
    ["fetch", "--dump", "html", T.unpack (productUrl item)]
    LBS.empty
  pure $ case code of
    ExitFailure n -> Left (WalmartRenderFailed
      (T.pack (rendererExecutable renderer) <> " exited with " <> T.pack (show n) <> ": "
        <> T.take 2000 (TE.decodeUtf8With lenientDecode (LBS.toStrict err))))
    ExitSuccess ->
      let html = TE.decodeUtf8With lenientDecode (LBS.toStrict out)
      in case extractNextData html of
        Nothing -> Left (WalmartRenderFailed
          ("the rendered page for item " <> unUsItemId item <> " carries no product data ("
            <> T.pack (show (T.length html)) <> " characters)"))
        Just payload -> case Aeson.eitherDecodeStrict (TE.encodeUtf8 payload) of
          Left decodeErr -> Left (WalmartJsonDecodeError decodeErr (BodyPreview (T.take 8000 payload)))
          Right value -> either (Left . WalmartParseError "product page") Right (parseProductDetail value)

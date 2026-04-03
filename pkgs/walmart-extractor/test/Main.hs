{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Text (Text)
import Data.Text qualified as T
import Test.QuickCheck
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck (testProperty)

import WalmartExtractor (collectAll, parseHashPair, parseScriptUrls)

newtype AlphaText = AlphaText Text deriving stock (Show)
instance Arbitrary AlphaText where
  arbitrary = AlphaText . T.pack <$> listOf1 (elements (['a'..'z'] <> ['A'..'Z'] <> [' ']))

newtype HexHash = HexHash Text deriving stock (Show)
instance Arbitrary HexHash where
  arbitrary = HexHash . T.pack <$> vectorOf 64 (elements (['0'..'9'] <> ['a'..'f']))

main :: IO ()
main = defaultMain $ testGroup "walmart-extractor"
  [ parserTests
  , propertyTests
  , adversarialTests
  ]

parserTests :: TestTree
parserTests = testGroup "Parsers"
  [ testCase "extract script URLs from HTML" $ do
      let html = T.unlines
            [ "<script src=\"https://i5.walmartimages.com/chunk-abc.js\"></script>"
            , "<script src=\"/local.js\"></script>"
            , "<script src=\"https://i5.walmartimages.com/other-def.js\"></script>"
            ]
      let urls = parseScriptUrls html
      length urls @?= 2
      head urls @?= "https://i5.walmartimages.com/chunk-abc.js"

  , testCase "extract hash pairs from JS" $ do
      let js = "blah name:\"PurchaseHistoryV2\",hash:\"a7067e4c7c36457fdef25b48d8c1ab5574f2e5f64580cdd5b1202b32c39928f6\" more"
      let pairs = collectAll parseHashPair js
      length pairs @?= 1
      fst (head pairs) @?= "PurchaseHistoryV2"

  , testCase "no script URLs in empty HTML" $
      parseScriptUrls "" @?= []

  , testCase "no hash pairs in random text" $
      collectAll parseHashPair "no hashes here" @?= []

  , testCase "hash with uppercase hex is rejected" $
      collectAll parseHashPair
        "name:\"Foo\",hash:\"A7067E4C7C36457FDEF25B48D8C1AB5574F2E5F64580CDD5B1202B32C39928F6\""
        @?= []

  , testCase "hash with 63 chars is rejected" $
      collectAll parseHashPair
        "name:\"Foo\",hash:\"a7067e4c7c36457fdef25b48d8c1ab5574f2e5f64580cdd5b1202b32c39928f\""
        @?= []

  , testCase "script URL without .js extension is skipped" $
      parseScriptUrls "<script src=\"https://i5.walmartimages.com/chunk.css\"></script>"
        @?= []

  , testCase "multiple hashes in one JS chunk" $ do
      let js = T.concat
            [ "name:\"Op1\",hash:\"" <> T.replicate 64 "a" <> "\""
            , " other stuff "
            , "name:\"Op2\",hash:\"" <> T.replicate 64 "b" <> "\""
            ]
      let pairs = collectAll parseHashPair js
      length pairs @?= 2
      fst (head pairs) @?= "Op1"

  , testCase "parser survives megabytes of garbage" $ do
      let garbage = T.replicate 1000000 "x"
      parseScriptUrls garbage @?= []
      collectAll parseHashPair garbage @?= []
  ]

propertyTests :: TestTree
propertyTests = testGroup "Properties"
  [ testProperty "hash parser roundtrips valid pairs" $
      \(AlphaText name, HexHash hash) ->
        let input = "prefix name:\"" <> name <> "\",hash:\"" <> hash <> "\" suffix"
        in collectAll parseHashPair input == [(name, hash)]
  ]

adversarialTests :: TestTree
adversarialTests = testGroup "Adversarial"
  [ testProperty "parser never crashes on arbitrary bytes" $
      \(s :: String) ->
        let t = T.pack s
        in parseScriptUrls t `seq` collectAll parseHashPair t `seq` True
  ]

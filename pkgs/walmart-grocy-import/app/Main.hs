{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime, addUTCTime, getCurrentTime, nominalDay)
import Network.HTTP.Client (newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Options.Applicative
import System.Directory (createDirectoryIfMissing, getHomeDirectory)
import System.FilePath ((</>))

import WalmartGrocy.App (runImport, runList)
import WalmartGrocy.Cookies (getFirefoxCookies)
import WalmartGrocy.Types

data Command
  = List ListOpts
  | Import ImportOpts

data ListOpts = ListOpts
  { loSince :: Maybe Text
  , loLimit :: Int
  }

data ImportOpts = ImportOpts
  { imSince    :: Maybe Text
  , imLimit    :: Int
  , imDryRun   :: Bool
  , imForce    :: Bool
  , imGrocyUrl :: Text
  , imGrocyKey :: Text
  }

parseSince :: Text -> IO UTCTime
parseSince input = do
  now <- getCurrentTime
  case T.words (T.toLower input) of
    [nStr, unitStr, _] ->
      let n = read (T.unpack nStr) :: Int
          unit = T.dropWhileEnd (== 's') unitStr
          seconds = case unit of
            "day"  -> fromIntegral n * nominalDay
            "hour" -> fromIntegral n * 3600
            "week" -> fromIntegral n * 7 * nominalDay
            _      -> error ("Unknown time unit: " <> T.unpack unitStr)
      in pure (addUTCTime (negate seconds) now)
    _ -> error ("Cannot parse since: " <> T.unpack input)

globalParser :: Parser (Bool, Command)
globalParser = (,)
  <$> switch (long "verbose" <> short 'v' <> help "Enable verbose logging")
  <*> subparser
    ( command "list"
        (info (List <$> listParser) (progDesc "List recent Walmart orders"))
   <> command "import"
        (info (Import <$> importParser) (progDesc "Import orders into Grocy"))
    )

listParser :: Parser ListOpts
listParser = ListOpts
  <$> optional (strOption (long "since" <> help "Time filter, e.g. '7 days ago'"))
  <*> option auto (long "limit" <> value 10 <> help "Max orders to fetch")

importParser :: Parser ImportOpts
importParser = ImportOpts
  <$> optional (strOption (long "since" <> help "Time filter, e.g. '3 days ago'"))
  <*> option auto (long "limit" <> value 10 <> help "Max orders to fetch")
  <*> switch (long "dry-run" <> help "Show what would be imported")
  <*> switch (long "force" <> help "Re-import already imported orders")
  <*> strOption (long "grocy-url" <> help "Grocy instance URL")
  <*> strOption (long "grocy-api-key" <> help "Grocy API key")

main :: IO ()
main = do
  (verbose, cmd) <- execParser
    (info (globalParser <**> helper)
      (fullDesc <> progDesc "Import Walmart order history into Grocy"))

  let verbosity = if verbose then Verbose else Quiet

  mgr <- newManager tlsManagerSettings
  cookies <- getFirefoxCookies ".walmart.com"
  home <- getHomeDirectory
  let dataDir = home </> ".local" </> "share" </> "walmart-grocy-import"
  createDirectoryIfMissing True dataDir

  case cmd of
    List lo -> do
      mSince <- traverse parseSince (loSince lo)
      summaries <- runList mgr cookies dataDir mSince (loLimit lo)
      mapM_ printSummary summaries

    Import io -> do
      mSince <- traverse parseSince (imSince io)
      let grocyEnv = GrocyEnv
            { geBaseUrl = imGrocyUrl io
            , geApiKey  = imGrocyKey io
            , geManager = mgr
            }
          stateFile = dataDir </> "state.json"
          opts = ImportOptions
            { ioSince  = mSince
            , ioLimit  = imLimit io
            , ioDryRun = imDryRun io
            , ioForce  = imForce io
            }
      results <- runImport mgr cookies grocyEnv dataDir stateFile verbosity opts
      mapM_ printResult results
      let totalMatched = sum (map (length . irMatched) results)
          totalCreated = sum (map (length . irCreated) results)
          prefix = if imDryRun io then "[DRY RUN] " else "" :: String
      putStrLn (prefix <> "Import complete: "
        <> show totalMatched <> " matched, "
        <> show totalCreated <> " created")

printSummary :: OrderSummary -> IO ()
printSummary s =
  putStrLn ("  " <> T.unpack (unOrderId (osOrderId s))
    <> "  " <> show (osItemCount s) <> " items  "
    <> T.unpack (osStatus s))

printResult :: ImportResult -> IO ()
printResult r = do
  putStrLn ("\n  Order " <> T.unpack (unOrderId (irOrderId r)) <> ":")
  mapM_ printMatched (irMatched r)
  mapM_ printCreated (irCreated r)

printMatched :: (WalmartItem, GrocyProduct) -> IO ()
printMatched (item, gp) =
  putStrLn ("    = " <> T.unpack (wiName item) <> priceStr item
    <> " -> " <> T.unpack (gpName gp))

printCreated :: (WalmartItem, GrocyProduct) -> IO ()
printCreated (item, _) =
  putStrLn ("    + " <> T.unpack (wiName item) <> priceStr item)

priceStr :: WalmartItem -> String
priceStr item = case wiLinePrice item of
  Just p  -> " $" <> show p
  Nothing -> ""

{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime, addUTCTime, getCurrentTime, nominalDay)
import Options.Applicative
import System.Directory (createDirectoryIfMissing, getHomeDirectory)
import System.Exit (die)
import System.FilePath ((</>))
import Text.Read (readMaybe)

import BrowserCookies (CookieError (..), getFirefoxCookies)
import Grocy (GrocyError (..), ObjectCollection (..))
import Grocy qualified
import Walmart qualified
import Walmart.Types (OrderId (..), OrderSummary (..), WalmartError (..), WalmartItem (..))
import WalmartGrocy.App (runImport, runList)
import WalmartGrocy.Config (Config (..), defaultConfigPath, loadConfig, renderConfigError)
import WalmartGrocy.Types

data Command
  = List ListOpts
  | Import ImportOpts

data ListOpts = ListOpts
  { loSince :: Maybe Text
  , loLimit :: Int
  }

data ImportOpts = ImportOpts
  { imSince      :: Maybe Text
  , imLimit      :: Int
  , imDryRun     :: Bool
  , imForce      :: Bool
  , imConfigPath :: Maybe FilePath
  }

data CliError
  = UnknownTimeUnit Text
  | InvalidSinceFormat Text

parseSince :: Text -> IO (Either CliError UTCTime)
parseSince input = do
  now <- getCurrentTime
  pure $ case T.words (T.toLower input) of
    [nStr, unitStr, "ago"] ->
      case readMaybe (T.unpack nStr) :: Maybe Int of
        Nothing -> Left (InvalidSinceFormat input)
        Just n ->
          let unit = T.dropWhileEnd (== 's') unitStr
          in case unit of
            "day"  -> Right (addUTCTime (negate (fromIntegral n * nominalDay)) now)
            "hour" -> Right (addUTCTime (negate (fromIntegral n * 3600)) now)
            "week" -> Right (addUTCTime (negate (fromIntegral n * 7 * nominalDay)) now)
            _otherUnit -> Left (UnknownTimeUnit unitStr)
    _otherShape -> Left (InvalidSinceFormat input)

commandParser :: Parser Command
commandParser = subparser
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
  <*> switch (long "dry-run" <> help "Show what would be imported without touching Grocy")
  <*> switch (long "force" <> help "Re-import already imported orders")
  <*> optional (strOption
        (long "config" <> metavar "FILE"
         <> help "Config file (default: $XDG_CONFIG_HOME/walmart-grocy-import/config.toml)"))

main :: IO ()
main = do
  cmd <- execParser
    (info (commandParser <**> helper)
      (fullDesc <> progDesc "Import Walmart order history into Grocy"))

  cookieResult <- getFirefoxCookies ".walmart.com"
  cookies <- either (die . renderAppError . AppCookieError) pure cookieResult

  walmartEnv <- Walmart.newEnv cookies
  home <- getHomeDirectory
  let dataDir = home </> ".local" </> "share" </> "walmart-grocy-import"
  createDirectoryIfMissing True dataDir

  case cmd of
    List lo -> do
      mSince <- traverse requireParseSince (loSince lo)
      result <- runList walmartEnv mSince (loLimit lo)
      summaries <- either (die . renderAppError) pure result
      mapM_ printSummary summaries

    Import io -> do
      mSince <- traverse requireParseSince (imSince io)
      configPath <- maybe defaultConfigPath pure (imConfigPath io)
      configResult <- loadConfig configPath
      config <- either (die . renderConfigError) pure configResult
      grocy <- Grocy.newEnv (cfgGrocyUrl config) (cfgGrocyApiKey config)
      let stateFile = dataDir </> "state.json"
          opts = ImportOptions
            { ioSince = mSince
            , ioLimit = imLimit io
            , ioMode  = if imDryRun io then DryRun else Execute
            , ioForce = imForce io
            }
      result <- runImport walmartEnv grocy (cfgSetup config) stateFile opts
      outcome <- either (die . renderAppError) pure result
      printOutcome outcome

requireParseSince :: Text -> IO UTCTime
requireParseSince input = do
  result <- parseSince input
  either (die . renderCliError) pure result

printSummary :: OrderSummary -> IO ()
printSummary s =
  putStrLn ("  " <> T.unpack (unOrderId (osOrderId s))
    <> "  " <> show (osItemCount s) <> " items"
    <> maybe "" (\status -> "  " <> T.unpack status) (osStatus s))

printOutcome :: ImportOutcome -> IO ()
printOutcome (PlannedOnly plans) = do
  mapM_ printPlan plans
  let actions = concatMap ipActions plans
      matched = length [() | StockExisting _ _ <- actions]
      created = length [() | CreateAndStock _ <- actions]
  putStrLn (summaryLine "[DRY RUN] Would import" matched created)
printOutcome (Imported results) = do
  mapM_ printResult results
  let executed = concatMap irActions results
      matched = length [() | Stocked _ _ <- executed]
      created = length [() | Created _ _ <- executed]
  putStrLn (summaryLine "Import complete" matched created)

summaryLine :: String -> Int -> Int -> String
summaryLine prefix matched created =
  prefix <> ": " <> show matched <> " matched, " <> show created <> " created"

printPlan :: ImportPlan -> IO ()
printPlan plan = do
  putStrLn ("\n  Order " <> T.unpack (unOrderId (ipOrderId plan)) <> ":")
  mapM_ printAction (ipActions plan)

printAction :: Action -> IO ()
printAction (StockExisting item matched) =
  putStrLn ("    = " <> T.unpack (wiName item) <> priceStr item
    <> " -> " <> T.unpack (Grocy.productName matched))
printAction (CreateAndStock item) =
  putStrLn ("    + " <> T.unpack (wiName item) <> priceStr item)

printResult :: ImportResult -> IO ()
printResult result = do
  putStrLn ("\n  Order " <> T.unpack (unOrderId (irOrderId result)) <> ":")
  mapM_ printExecuted (irActions result)

printExecuted :: ExecutedAction -> IO ()
printExecuted (Stocked item matched) =
  putStrLn ("    = " <> T.unpack (wiName item) <> priceStr item
    <> " -> " <> T.unpack (Grocy.productName matched))
printExecuted (Created item _) =
  putStrLn ("    + " <> T.unpack (wiName item) <> priceStr item)

priceStr :: WalmartItem -> String
priceStr item = case wiLinePrice item of
  Just cents ->
    let total = abs (toInteger cents)
        dollars = total `div` 100
        remainder = total `mod` 100
    in " $" <> show dollars <> "." <> (if remainder < 10 then "0" else "") <> show remainder
  Nothing -> ""

renderCliError :: CliError -> String
renderCliError (UnknownTimeUnit unit) =
  "Unknown time unit: " <> T.unpack unit <> ". Use day(s), hour(s), or week(s)."
renderCliError (InvalidSinceFormat input) =
  "Cannot parse --since value: " <> T.unpack input <> ". Expected format: '7 days ago'"

renderAppError :: AppError -> String
renderAppError (AppCookieError (NoProfilesIni p)) =
  "No Firefox profiles.ini at " <> p <> ". Is Firefox set up on this machine?"
renderAppError (AppCookieError (NoCookiesFound d p)) =
  "No cookies found for " <> T.unpack d <> " in " <> p
  <> ". Log into walmart.com in Firefox first."
renderAppError (AppCookieError (NoDefaultProfile p)) =
  "Could not find default Firefox profile in " <> p
renderAppError (AppWalmartError WalmartHashRotated) =
  "Walmart returned 400 -- hash may have rotated. Run walmart-extractor to update endpoints."
renderAppError (AppWalmartError WalmartRateLimited) =
  "Rate limited -- log into walmart.com in Firefox to refresh cookies."
renderAppError (AppWalmartError (WalmartAccessDenied code)) =
  "Access denied (HTTP " <> show code <> ") -- cookies expired. Log into walmart.com."
renderAppError (AppWalmartError (WalmartHttpError code)) =
  "Walmart API returned HTTP " <> show code
renderAppError (AppWalmartError (WalmartParseError op err)) =
  "Failed to parse " <> T.unpack op <> ": " <> err
renderAppError (AppWalmartError (WalmartJsonDecodeError err preview)) =
  "JSON decode failed: " <> err <> "\nResponse: " <> preview
renderAppError (AppGrocyError (GrocyHttpError path code)) =
  "Grocy " <> T.unpack path <> " returned HTTP " <> show code
renderAppError (AppGrocyError (GrocyParseError path msg)) =
  "Failed to parse Grocy response from " <> T.unpack path <> ": " <> T.unpack msg
renderAppError (AppGrocyError (GrocyObjectNotFound collection name)) =
  "Required Grocy " <> collectionNoun collection <> " not found: " <> T.unpack name
renderAppError (AppStateCorrupt path err) =
  "State file " <> path <> " is corrupt: " <> err
  <> "\nFix or remove it; removing it will re-import every order on the next run."

collectionNoun :: ObjectCollection -> String
collectionNoun Locations         = "location"
collectionNoun ShoppingLocations = "shopping location"
collectionNoun QuantityUnits     = "quantity unit"

{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (unless)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime, addUTCTime, getCurrentTime, nominalDay)
import Money qualified
import Options.Applicative
import System.Directory (createDirectoryIfMissing, getHomeDirectory)
import System.Exit (die, exitFailure)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

import BrowserCookies (CookieError (..), getFirefoxCookies)
import Grocy (ApiPath (..), GrocyError (..), ObjectCollection (..))
import Grocy qualified
import Walmart qualified
import Walmart.Types (BodyPreview (..), OrderId (..), OrderSummary (..), WalmartError (..), WalmartItem (..))
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
    List listOpts -> do
      mSince <- traverse requireParseSince (loSince listOpts)
      result <- runList walmartEnv mSince (loLimit listOpts)
      summaries <- either (die . renderAppError) pure result
      mapM_ printSummary summaries

    Import importOpts -> do
      mSince <- traverse requireParseSince (imSince importOpts)
      configPath <- maybe defaultConfigPath pure (imConfigPath importOpts)
      configResult <- loadConfig configPath
      config <- either (die . renderConfigError) pure configResult
      grocy <- Grocy.newEnv (cfgGrocyUrl config) (cfgGrocyApiKey config)
      let stateFile = dataDir </> "state.json"
          opts = ImportOptions
            { ioSince = mSince
            , ioLimit = imLimit importOpts
            , ioMode  = if imDryRun importOpts then DryRun else Execute
            , ioForce = imForce importOpts
            }
      result <- runImport walmartEnv grocy (cfgSetup config) stateFile opts
      report <- either (die . renderAppError) pure result
      mapM_ printSkipped (reportSkipped report)
      printOutcome (reportOutcome report)
      case reportOutcome report of
        Imported _ failures -> unless (null failures) exitFailure
        PlannedOnly _       -> pure ()

requireParseSince :: Text -> IO UTCTime
requireParseSince input = do
  result <- parseSince input
  either (die . renderCliError) pure result

printSummary :: OrderSummary -> IO ()
printSummary s =
  putStrLn ("  " <> T.unpack (unOrderId (osOrderId s))
    <> "  " <> show (osItemCount s) <> " items"
    <> maybe "" (\status -> "  " <> T.unpack status) (osStatus s))

printSkipped :: SkippedOrder -> IO ()
printSkipped skippedOrder = hPutStrLn stderr $
  "Skipped order " <> T.unpack (unOrderId (soOrderId skippedOrder))
  <> ": " <> renderWalmartError (soError skippedOrder)

printOutcome :: ImportOutcome -> IO ()
printOutcome (PlannedOnly plans) = do
  mapM_ printPlan plans
  let actions = concatMap ipActions plans
      matched = length [() | StockExisting _ _ <- actions]
      created = length [() | CreateAndStock _ <- actions]
  putStrLn (summaryLine "[DRY RUN] Would import" matched created)
printOutcome (Imported results failures) = do
  mapM_ printResult results
  let executed = concatMap irActions results
      matched = length [() | Stocked _ _ <- executed]
      created = length [() | Created _ _ <- executed]
  putStrLn (summaryLine "Import complete" matched created)
  mapM_ printFailure failures

printFailure :: OrderFailure -> IO ()
printFailure failure = hPutStrLn stderr $
  "\nOrder " <> T.unpack (unOrderId (ofOrderId failure))
  <> " failed: " <> renderGrocyError (ofError failure)
  <> "\n  Items not imported:"
  <> concatMap (\a -> "\n    " <> T.unpack (wiName (actionItem a))) (ofNotExecuted failure)
  <> if null (ofStocked failure)
       then "\n  Nothing from this order was stocked; it will be retried on the next run."
       else "\n  " <> show (length (ofStocked failure))
            <> " item(s) were already stocked, so the order is marked imported"
            <> " and will not be retried."

actionItem :: Action -> WalmartItem
actionItem (CreateAndStock item)   = item
actionItem (StockExisting item _) = item

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
    let rendered = Money.discreteToDecimal Money.defaultDecimalConf Money.Round cents
    in if cents < 0
         then " -$" <> T.unpack (T.drop 1 rendered)
         else " $" <> T.unpack rendered
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
renderAppError (AppWalmartError walmartErr) = renderWalmartError walmartErr
renderAppError (AppGrocyError grocyErr) = renderGrocyError grocyErr
renderAppError (AppStateCorrupt path err) =
  "State file " <> path <> " is corrupt: " <> err
  <> "\nFix or remove it; removing it will re-import every order on the next run."

renderWalmartError :: WalmartError -> String
renderWalmartError WalmartBadRequest =
  "Walmart rejected the request (HTTP 400) -- the endpoint hash may have rotated. Run walmart-extractor to update endpoints."
renderWalmartError WalmartRateLimited =
  "Rate limited -- log into walmart.com in Firefox to refresh cookies."
renderWalmartError WalmartAccessDenied =
  "Access denied -- cookies expired. Log into walmart.com."
renderWalmartError (WalmartHttpError code) =
  "Walmart API returned HTTP " <> show code
renderWalmartError (WalmartParseError op err) =
  "Failed to parse " <> T.unpack op <> ": " <> err
renderWalmartError (WalmartJsonDecodeError err preview) =
  "JSON decode failed: " <> err <> "\nResponse: " <> unBodyPreview preview

renderGrocyError :: GrocyError -> String
renderGrocyError (GrocyHttpError path code preview) =
  "Grocy " <> T.unpack (unApiPath path) <> " returned HTTP " <> show code
  <> ": " <> T.unpack preview
renderGrocyError (GrocyParseError path msg) =
  "Failed to parse Grocy response from " <> T.unpack (unApiPath path) <> ": " <> T.unpack msg
renderGrocyError (GrocyObjectNotFound collection name) =
  "Required Grocy " <> collectionNoun collection <> " not found: " <> T.unpack name

collectionNoun :: ObjectCollection -> String
collectionNoun Locations         = "location"
collectionNoun ShoppingLocations = "shopping location"
collectionNoun QuantityUnits     = "quantity unit"

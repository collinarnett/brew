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

import BrowserCookies (CookieConfig (..), CookieError (..), getFirefoxCookies)
import Grocy qualified
import Grocy.Types (GrocyError (..), GrocyProduct (..), SetupConfig (..))
import Walmart qualified
import Walmart.Types (OrderId (..), OrderSummary (..), WalmartError (..), WalmartItem (..))
import WalmartGrocy.App (runImport, runList)
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

data CliError
  = UnknownTimeUnit Text
  | InvalidSinceFormat Text

parseSince :: Text -> IO (Either CliError UTCTime)
parseSince input = do
  now <- getCurrentTime
  pure $ case T.words (T.toLower input) of
    [nStr, unitStr, _] ->
      case readMaybe (T.unpack nStr) :: Maybe Int of
        Nothing -> Left (InvalidSinceFormat input)
        Just n ->
          let unit = T.dropWhileEnd (== 's') unitStr
          in case unit of
            "day"  -> Right (addUTCTime (negate (fromIntegral n * nominalDay)) now)
            "hour" -> Right (addUTCTime (negate (fromIntegral n * 3600)) now)
            "week" -> Right (addUTCTime (negate (fromIntegral n * 7 * nominalDay)) now)
            _      -> Left (UnknownTimeUnit unitStr)
    _otherWordCount -> Left (InvalidSinceFormat input)

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

  let cookieCfg = CookieConfig { ccVerbose = verbose }
  cookieResult <- getFirefoxCookies cookieCfg ".walmart.com"
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
      grocyEnv <- Grocy.newEnv (imGrocyUrl io) (imGrocyKey io)
      let stateFile = dataDir </> "state.json"
          setupCfg = SetupConfig
            { scLocationName         = "Pantry"
            , scShoppingLocationName = "Walmart"
            , scQuantityUnitName     = "Piece"
            }
          opts = ImportOptions
            { ioSince  = mSince
            , ioLimit  = imLimit io
            , ioDryRun = imDryRun io
            , ioForce  = imForce io
            }
          verbosity = if verbose then Verbose else Quiet
      result <- runImport walmartEnv grocyEnv setupCfg stateFile verbosity opts
      results <- either (die . renderAppError) pure result
      mapM_ printResult results
      let totalMatched = sum (map (length . irMatched) results)
          totalCreated = sum (map (length . irCreated) results)
          prefix = if imDryRun io then "[DRY RUN] " else "" :: String
      putStrLn (prefix <> "Import complete: "
        <> show totalMatched <> " matched, "
        <> show totalCreated <> " created")

requireParseSince :: Text -> IO UTCTime
requireParseSince input = do
  result <- parseSince input
  either (die . renderCliError) pure result

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
renderAppError (AppGrocyError (GrocyDecodeError err)) =
  "Failed to decode Grocy response: " <> err
renderAppError (AppGrocyError (GrocyParseError err)) =
  "Failed to parse Grocy products: " <> err
renderAppError (AppGrocyError (GrocyProductNotFound name)) =
  "Product not found and could not be created: " <> T.unpack name
renderAppError (AppGrocyError (GrocyEntityNotFound typ name)) =
  "Required Grocy entity not found: " <> T.unpack typ <> "/" <> T.unpack name
renderAppError (AppGrocyError (GrocyCreateError typ err)) =
  "Failed to create " <> T.unpack typ <> ": " <> err
renderAppError (AppGrocyError (GrocyMissingId typ)) =
  "No created_object_id in " <> T.unpack typ <> " response"
renderAppError (AppGrocyError (GrocyHttpError path code)) =
  "Grocy GET " <> T.unpack path <> " returned HTTP " <> show code
renderAppError (AppGrocyError (GrocyIdParseError raw)) =
  "Could not parse Grocy ID: " <> raw

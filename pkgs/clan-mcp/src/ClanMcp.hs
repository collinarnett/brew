{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE RecordWildCards #-}

module ClanMcp
  ( ClanCommand (..)
  , ClanArgument (..)
  , loadCommands
  , listTools
  , callTool
  ) where

import Data.Aeson (FromJSON (..), Value (..), eitherDecodeFileStrict, withObject, (.:), (.:?), (.!=))
import Data.Aeson qualified as Aeson
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Vector qualified as V
import MCP.Server.Types
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)

data ClanCommand = ClanCommand
  { path :: [Text]
  , description :: Text
  , helpText :: Text
  , arguments :: [ClanArgument]
  }

data ClanArgument = ClanArgument
  { name :: Text
  , help :: Text
  , required :: Bool
  , positional :: Bool
  , argType :: Text
  , flags :: [Text]
  , choices :: [Text]
  , array :: Bool
  }

instance FromJSON ClanCommand where
  parseJSON = withObject "ClanCommand" $ \o ->
    ClanCommand
      <$> o .: "path"
      <*> o .: "description"
      <*> o .: "help_text"
      <*> o .:? "arguments" .!= []

instance FromJSON ClanArgument where
  parseJSON = withObject "ClanArgument" $ \o ->
    ClanArgument
      <$> o .: "name"
      <*> o .:? "help" .!= ""
      <*> o .:? "required" .!= False
      <*> o .:? "positional" .!= False
      <*> o .:? "type" .!= "string"
      <*> o .:? "flags" .!= []
      <*> o .:? "choices" .!= []
      <*> o .:? "array" .!= False

loadCommands :: FilePath -> IO [ClanCommand]
loadCommands fp = either fail pure =<< eitherDecodeFileStrict fp

toolName :: ClanCommand -> Text
toolName cmd = T.intercalate "_" ("clan" : path cmd)

listTools :: [ClanCommand] -> [ToolDefinition]
listTools = map toToolDef
  where
    toToolDef cmd =
      ToolDefinition
        { toolDefinitionName = toolName cmd
        , toolDefinitionDescription = description cmd <> "\n\n" <> helpText cmd
        , toolDefinitionInputSchema = InputSchemaDefinitionObject
            { properties = map toProperty (filter (not . isCommonFlag) (arguments cmd))
            , MCP.Server.Types.required = [ClanMcp.name a | a <- arguments cmd, ClanMcp.required a]
            }
        , toolDefinitionTitle = Just ("clan " <> T.intercalate " " (path cmd))
        }

    toProperty ClanArgument{..} =
      ( name
      , InputSchemaDefinitionProperty
          { propertyType = case (argType, array) of
              ("boolean", _) -> "boolean"
              ("integer", _) -> "integer"
              ("number", _) -> "number"
              (_, True) -> "array"
              _ -> "string"
          , propertyDescription = help
          }
      )

    isCommonFlag a = ClanMcp.name a `elem` ["debug", "option"]

callTool :: [ClanCommand] -> McpSession IO -> ToolName -> [(ArgumentName, ArgumentValue)] -> IO (Either Error ToolResult)
callTool cmds _session toolN args =
  case filter (\c -> toolName c == toolN) cmds of
    [] -> pure $ Left $ UnknownTool toolN
    (cmd : _) -> do
      let cliArgs = map T.unpack (path cmd) <> concatMap (toCli cmd) args
      (code, out, err) <- readProcessWithExitCode "clan" cliArgs ""
      let output = out <> if null err then "" else "\n" <> err
          body = T.pack output <> case code of
            ExitSuccess -> ""
            ExitFailure n -> "\n[exit code " <> T.pack (show n) <> "]"
      pure $ Right $ case code of
        ExitSuccess -> toolText body
        ExitFailure _ -> toolError body

toCli :: ClanCommand -> (ArgumentName, ArgumentValue) -> [String]
toCli cmd (argName, argVal) =
  case filter (\a -> ClanMcp.name a == argName) (arguments cmd) of
    [] -> []
    (ClanArgument{..} : _)
      | argType == "boolean" -> [T.unpack (pickFlag flags) | argVal == "true"]
      | array, positional -> map T.unpack (parseArray argVal)
      | array -> T.unpack (pickFlag flags) : map T.unpack (parseArray argVal)
      | positional -> [T.unpack argVal]
      | otherwise -> [T.unpack (pickFlag flags), T.unpack argVal]

parseArray :: Text -> [Text]
parseArray t =
  case Aeson.decodeStrict (TE.encodeUtf8 t) of
    Just (Array v) -> [s | String s <- V.toList v]
    _ ->
      -- Handle Haskell Show format from mcp-server's jsonValueToText fallback,
      -- which produces e.g. Array [String "cmd",String "arg"] instead of JSON
      let parts = drop 1 (T.splitOn "String \"" t)
          strings = map (T.takeWhile (/= '"')) parts
      in if null strings then [t] else strings

pickFlag :: [Text] -> Text
pickFlag fs = case filter ("--" `T.isPrefixOf`) fs of
  (f : _) -> f
  [] -> case fs of
    (f : _) -> f
    [] -> ""

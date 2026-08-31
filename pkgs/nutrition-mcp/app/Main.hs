module Main (main) where

import MCP.Server
  ( HttpConfig (..)
  , runMcpServerHttpWithConfig
  , runMcpServerStdio
  )
import MCP.Server.Types
import System.Environment (getArgs)
import System.Exit (die)

import NutritionMcp qualified
import NutritionMcp.Config
import OpenFoodFacts qualified

data Transport = Stdio | Http Int

usage :: String
usage = "Usage: nutrition-mcp [--http <port>] [config.toml]"

parseArgs :: [String] -> IO (Transport, Maybe FilePath)
parseArgs [] = pure (Stdio, Nothing)
parseArgs [file] = pure (Stdio, Just file)
parseArgs ["--http", portStr] = (,Nothing) <$> parsePort portStr
parseArgs ["--http", portStr, file] = (,Just file) <$> parsePort portStr
parseArgs [file, "--http", portStr] = (,Just file) <$> parsePort portStr
parseArgs _ = fail usage

parsePort :: String -> IO Transport
parsePort portStr = case reads portStr of
  [(port, "")] -> pure (Http port)
  _ -> fail usage

main :: IO ()
main = do
  (transport, explicitPath) <- getArgs >>= parseArgs
  configPath <- maybe defaultConfigPath pure explicitPath
  configResult <- loadConfig configPath
  config <- either (die . renderConfigError) pure configResult
  env <- OpenFoodFacts.newEnv (cfgUserAgent config)

  let info = McpServerInfo
        { serverName = "nutrition-mcp"
        , serverVersion = "0.1.0"
        , serverInstructions =
            "Nutrition facts by package barcode, from the Open Food Facts\
            \ database: the label per 100 g and per serving, the serving\
            \ size, and the ingredient statement."
        }
      handlers = McpServerHandlers
        { prompts = Nothing
        , resources = Nothing
        , resourceTemplates = Nothing
        , tools = Just (pure NutritionMcp.listTools, NutritionMcp.callTool env)
        , completions = Nothing
        }

  case transport of
    Stdio -> runMcpServerStdio info handlers
    Http port ->
      runMcpServerHttpWithConfig
        HttpConfig
          { httpPort = port
          , httpHost = "localhost"
          , httpEndpoint = "/mcp"
          , httpVerbose = False
          }
        info
        handlers

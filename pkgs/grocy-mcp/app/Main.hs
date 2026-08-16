module Main (main) where

import MCP.Server
  ( HttpConfig (..)
  , runMcpServerHttpWithConfig
  , runMcpServerStdio
  )
import MCP.Server.Types
import System.Environment (getArgs)
import System.Exit (die)

import Grocy qualified
import GrocyMcp qualified
import GrocyMcp.Config

data Transport = Stdio | Http Int

usage :: String
usage = "Usage: grocy-mcp [--http <port>] [config.toml]"

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
  env <- Grocy.newEnv (cfgGrocyUrl config) (cfgGrocyApiKey config)

  let info = McpServerInfo
        { serverName = "grocy-mcp"
        , serverVersion = "0.1.0"
        , serverInstructions =
            "Grocy inventory access: list and create products, record\
            \ stock purchases, and resolve locations, shopping locations,\
            \ and quantity units by name."
        }
      handlers = McpServerHandlers
        { prompts = Nothing
        , resources = Nothing
        , resourceTemplates = Nothing
        , tools = Just (pure GrocyMcp.listTools, GrocyMcp.callTool env)
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

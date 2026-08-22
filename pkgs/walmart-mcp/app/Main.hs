module Main (main) where

import MCP.Server
  ( HttpConfig (..)
  , runMcpServerHttpWithConfig
  , runMcpServerStdio
  )
import MCP.Server.Types
import System.Environment (getArgs)
import System.Exit (die)

import WalmartMcp qualified
import WalmartMcp.Config

data Transport = Stdio | Http Int

usage :: String
usage = "Usage: walmart-mcp [--http <port>] [config.toml]"

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

  let info = McpServerInfo
        { serverName = "walmart-mcp"
        , serverVersion = "0.1.0"
        , serverInstructions =
            "Walmart access through the local Firefox session: search the\
            \ catalogue by keyword and category, list order history, and\
            \ fetch per-order detail with items and prices. Endpoint\
            \ hashes are discovered from Walmart's current frontend build\
            \ and refreshed automatically when one is retired."
        }
      handlers = McpServerHandlers
        { prompts = Nothing
        , resources = Nothing
        , resourceTemplates = Nothing
        , tools = Just (pure WalmartMcp.listTools, WalmartMcp.callTool config)
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

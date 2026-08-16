module Main (main) where

import MCP.Server
  ( HttpConfig (..)
  , runMcpServerHttpWithConfig
  , runMcpServerStdio
  )
import MCP.Server.Types
import System.Environment (getArgs)

import WalmartMcp qualified

data Transport = Stdio | Http Int

usage :: String
usage = "Usage: walmart-mcp [--http <port>]"

parseArgs :: [String] -> IO Transport
parseArgs [] = pure Stdio
parseArgs ["--http", portStr] = case reads portStr of
  [(port, "")] -> pure (Http port)
  _ -> fail usage
parseArgs _ = fail usage

main :: IO ()
main = do
  transport <- getArgs >>= parseArgs

  let info = McpServerInfo
        { serverName = "walmart-mcp"
        , serverVersion = "0.1.0"
        , serverInstructions =
            "Read-only access to Walmart order history through the local\
            \ Firefox session. List orders, then fetch per-order detail\
            \ with items and prices."
        }
      handlers = McpServerHandlers
        { prompts = Nothing
        , resources = Nothing
        , resourceTemplates = Nothing
        , tools = Just (pure WalmartMcp.listTools, WalmartMcp.callTool)
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

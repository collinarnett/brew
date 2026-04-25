module Main (main) where

import MCP.Server
  ( HttpConfig (..)
  , runMcpServerHttpWithConfig
  , runMcpServerStdio
  )
import MCP.Server.Types
import System.Environment (getArgs)
import System.IO (hPutStrLn, stderr)

import ClanMcp

data Transport = Stdio | Http Int

usage :: String
usage = "Usage: clan-mcp [--http <port>] <commands.json>"

parseArgs :: [String] -> IO (Transport, FilePath)
parseArgs ["--http", portStr, file] = httpMode portStr file
parseArgs [file, "--http", portStr] = httpMode portStr file
parseArgs [file] = pure (Stdio, file)
parseArgs _ = fail usage

httpMode :: String -> FilePath -> IO (Transport, FilePath)
httpMode portStr file = case reads portStr of
  [(port, "")] -> pure (Http port, file)
  _ -> fail usage

main :: IO ()
main = do
  (transport, commandsFile) <- getArgs >>= parseArgs

  commands <- loadCommands commandsFile
  hPutStrLn stderr $ "clan-mcp: loaded " <> show (length commands) <> " tools"

  let info = McpServerInfo
        { serverName = "clan-mcp"
        , serverVersion = "0.1.0"
        , serverInstructions = "MCP server exposing the clan CLI. Each tool corresponds to a clan subcommand."
        }
      handlers = McpServerHandlers
        { prompts = Nothing
        , resources = Nothing
        , resourceTemplates = Nothing
        , tools = Just (pure (listTools commands), callTool commands)
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

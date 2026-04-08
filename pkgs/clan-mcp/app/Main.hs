module Main (main) where

import MCP.Server (runMcpServerStdio)
import MCP.Server.Types
import System.Environment (getArgs)
import System.IO (hPutStrLn, stderr)

import ClanMcp

main :: IO ()
main = do
  commandsFile <- getArgs >>= \case
    [f] -> pure f
    _ -> fail "Usage: clan-mcp <commands.json>"

  commands <- loadCommands commandsFile
  hPutStrLn stderr $ "clan-mcp: loaded " <> show (length commands) <> " tools"

  runMcpServerStdio
    McpServerInfo
      { serverName = "clan-mcp"
      , serverVersion = "0.1.0"
      , serverInstructions = "MCP server exposing the clan CLI. Each tool corresponds to a clan subcommand."
      }
    McpServerHandlers
      { prompts = Nothing
      , resources = Nothing
      , tools = Just (pure (listTools commands), callTool commands)
      }

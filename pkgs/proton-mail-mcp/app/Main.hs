module Main (main) where

import MCP.Server (runMcpServerStdio)
import MCP.Server.Types
import System.Environment (getArgs)
import System.Exit (die)

import ProtonMailMcp qualified
import ProtonMailMcp.Config

main :: IO ()
main = do
  configPath <- getArgs >>= \case
    [] -> defaultConfigPath
    [path] -> pure path
    _ -> die "Usage: proton-mail-mcp [config.toml]"
  config <- loadConfig configPath >>= either (die . renderConfigError) pure
  runMcpServerStdio
    McpServerInfo
      { serverName = "proton-mail-mcp"
      , serverVersion = "0.1.0.0"
      , serverInstructions = ProtonMailMcp.instructions
      }
    McpServerHandlers
      { prompts = Nothing
      , resources = Nothing
      , resourceTemplates = Nothing
      , tools = Just (pure ProtonMailMcp.listTools, ProtonMailMcp.callTool config)
      , completions = Nothing
      }

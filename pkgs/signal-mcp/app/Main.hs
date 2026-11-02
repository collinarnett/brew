module Main (main) where

import MCP.Server (runMcpServerStdio)
import MCP.Server.Types
import System.Environment (getArgs)
import System.Exit (die)

import SignalMcp.Config
import SignalMcp.Ingest (ingest)
import SignalMcp.Read qualified as Read
import SignalMcp.Send qualified as Send
import SignalMcp.Store (openWritable)

data Mode = Ingest | ReadServer | SendServer

main :: IO ()
main = do
  (mode, configPath) <- getArgs >>= \case
    [mode] -> (,) <$> parseMode mode <*> defaultConfigPath
    [mode, path] -> (,path) <$> parseMode mode
    _ -> usage
  config <- loadConfig configPath >>= either (die . renderConfigError) pure
  case mode of
    ReadServer -> do
      history <- Read.historyAt (cfgDatabase config)
      serve "signal" Read.instructions Read.listTools (Read.callTool history)
    SendServer -> do
      store <- openWritable (cfgDatabase config)
      serve "signal-send" Send.instructions Send.listTools (Send.callTool (cfgDaemon config) store)
    Ingest -> do
      openWritable (cfgDatabase config) >>= ingest (cfgDaemon config)
  where
    parseMode = \case
      "ingest" -> pure Ingest
      "read" -> pure ReadServer
      "send" -> pure SendServer
      _ -> usage
    usage = die "Usage: signal-mcp (ingest | read | send) [config.toml]"
    serve name serverInstructions toolList handler =
      runMcpServerStdio
        McpServerInfo {serverName = name, serverVersion = "0.1.0.0", serverInstructions = serverInstructions}
        McpServerHandlers
          { prompts = Nothing
          , resources = Nothing
          , resourceTemplates = Nothing
          , tools = Just (pure toolList, handler)
          , completions = Nothing
          }

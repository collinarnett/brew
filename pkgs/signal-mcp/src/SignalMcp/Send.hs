-- | The send server: one tool, which delivers a text message through the
-- daemon and adds it to the history, since signal-cli reports nothing back
-- about messages this device sends.
module SignalMcp.Send
  ( instructions
  , listTools
  , callTool
  ) where

import Data.Aeson (object, (.=))
import Data.Text (Text)
import Data.Text qualified as T
import MCP.Server.Types

import SignalMcp.Config (DaemonSettings (..))
import SignalMcp.Conversation
import SignalMcp.Daemon
import SignalMcp.Envelope (Event (..), Message (..), MessageKey (..), expiresAt)
import SignalMcp.Store (Store, applyEvents)
import SignalMcp.Tool

instructions :: Text
instructions =
  "Sends Signal messages as the owner. Every message goes to real people\
  \ immediately and cannot be recalled from here, so send only text the\
  \ owner asked for, to the conversation they meant."

listTools :: [ToolDefinition]
listTools =
  [ tool
      "signal_send"
      "Send a message"
      "Send a text message, as the owner, to a person or group. Delivery is immediate."
      [ textProperty "conversation" "A conversation id from the read server's signal_list_conversations or signal_find."
      , textProperty "message" "The text to send."
      ]
      ["conversation", "message"]
  ]

callTool :: DaemonSettings -> Store -> McpSession IO -> ToolName -> Arguments -> IO (Either Error ToolResult)
callTool settings store _session toolName args = case toolName of
  "signal_send" ->
    run "Sending through signal-cli failed: " sendRequest $ \(conversation, body) -> do
      sentAt <- withDaemon (daemonSocket settings) $ \conn -> do
        identity <- resolveIdentity conn (daemonAccount settings)
        timer <- disappearingTimer conn (identityAccount identity) (target conversation)
        sentAt <- sendMessage conn (identityAccount identity) (target conversation) body
        applyEvents store [Posted (sent conversation (identitySelf identity) sentAt timer body)]
        pure sentAt
      pure (jsonResult (object ["sent_at" .= renderTime sentAt, "conversation" .= renderConversation conversation]))
  _ -> pure (Left (UnknownTool toolName))
  where
    sendRequest =
      (,)
        <$> requiredArgument "conversation" parseConversation args
        <*> requiredArgument "message" nonBlank args
    nonBlank raw
      | T.null (T.strip raw) = Left "message must not be empty"
      | otherwise = Right raw
    target = \case
      Direct sid -> ToPerson sid
      Group gid -> ToGroup gid
    sent conversation self sentAt timer body =
      Message
        { messageConversation = conversation
        , messageKey = MessageKey self sentAt
        , messageBody = Just body
        , messageAttachments = []
        , messageViewOnce = False
        , messageQuote = Nothing
        , messageExpiresAt = expiresAt sentAt timer
        }

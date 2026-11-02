-- | The ingester: the one subscriber to the daemon's received messages,
-- writing each into the history. The daemon runs in manual receive mode,
-- so messages wait on Signal's servers whenever this is not attached.
module SignalMcp.Ingest
  ( ingest
  , contactEvents
  ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (race_)
import Control.Monad (forever)
import Data.Aeson (parseJSON)
import Data.Aeson.Types (parseEither)
import System.IO (hPutStrLn, stderr)

import SignalMcp.Config (DaemonSettings (..))
import SignalMcp.Daemon
import SignalMcp.Envelope
import SignalMcp.Store
import SignalMcp.Tool (currentTime)

ingest :: DaemonSettings -> Store -> IO ()
ingest settings store = do
  (identity, contacts, groups) <- withDaemon (daemonSocket settings) $ \conn -> do
    identity <- resolveIdentity conn (daemonAccount settings)
    (,,) identity <$> listContacts conn (identityAccount identity) <*> listGroups conn (identityAccount identity)
  recordSelf store (identitySelf identity)
  applyEvents store (concatMap contactEvents contacts <> [GroupNamed gid name | (gid, name) <- groups])
  race_ purging $
    withDaemon (daemonSocket settings) $ \conn ->
      subscribe conn (identityAccount identity) $ \value ->
        case parseEither parseJSON value of
          Right envelope -> applyEvents store (envelopeEvents envelope)
          -- The error names the field and the type found, never its value.
          Left err -> hPutStrLn stderr ("Skipped an envelope in a shape this ingester does not read: " <> err)
  where
    purging = forever $ do
      currentTime >>= purgeExpired store
      threadDelay (60 * 1000000)

contactEvents :: Contact -> [Event]
contactEvents contact =
  [ContactNamed (contactId contact) name | Just name <- [contactSavedName contact]]
    <> [PersonNamed (contactId contact) name | Just name <- [contactProfileName contact]]

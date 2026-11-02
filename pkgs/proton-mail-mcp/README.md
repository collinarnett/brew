# proton-mail-mcp

MCP server reading Proton Mail through a local
[Proton Mail Bridge](https://proton.me/mail/bridge). Bridge requires a paid
Proton plan.

- `mail_list_folders` — folders and labels.
- `mail_search` — search one folder, newest first.
- `mail_read` — headers, text body and the attachment list.
- `mail_save_draft` — save a plain-text draft to Drafts.

The server has no send, move or delete path and never speaks SMTP. Folders open
read-only with EXAMINE and fetches use BODY.PEEK, so reading leaves mail unread.
Attachment contents are never returned. Mail text is written by whoever sent
it, and the server tells its client to treat it as data.

`from`, `to` and `subject` match decoded headers. `text` is Bridge's raw byte
match, which misses words in base64 or quoted-printable bodies. Bodies in charsets other than ASCII, UTF-8 and
ISO-8859-1 come back as `body_error`.

Config at `$XDG_CONFIG_HOME/proton-mail-mcp/config.toml`:

```toml
[bridge]
username = "me@example.org"
password-file = "/path/to/bridge-password"
certificate-file = "/path/to/cert.pem"
draft-from = "Me <me@example.org>"
# host = "127.0.0.1"
# imap-port = 1143
```

`username` and the password are the ones `info` prints in `protonmail-bridge
--cli`, never the Proton account password. `certificate-file` is the
`cert.pem` from `cert export`; the server accepts exactly that certificate.

## Tests

`cabal test spec` covers the pure core. `cabal test integration` starts a real
dovecot over STARTTLS and needs `dovecot` and `openssl` on `PATH`.

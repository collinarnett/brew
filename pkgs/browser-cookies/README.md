# browser-cookies

Extract cookies from Firefox's SQLite database for use with `http-client`.

```haskell
import BrowserCookies

main :: IO ()
main = do
  Right cookies <- getFirefoxCookies ".example.com"
  -- cookies :: CookieJar, ready for http-client
```

## How it works

Firefox stores cookies in a SQLite database (`cookies.sqlite`) inside each profile directory. The library finds the default profile by parsing `~/.mozilla/firefox/profiles.ini`, copies the database to a temp file (Firefox holds a WAL lock on the original while running), queries for cookies matching the requested domain, and returns them as a standard `http-client` `CookieJar`.

The domain parameter is matched with a SQL `LIKE` prefix, so `".walmart.com"` picks up cookies for `www.walmart.com`, `.walmart.com`, etc.

## Errors

```haskell
data CookieError
  = NoProfilesIni FilePath         -- no ~/.mozilla/firefox/profiles.ini
  | NoDefaultProfile FilePath      -- couldn't find Default=1 in profiles.ini
  | NoCookiesFound Text FilePath   -- no cookies for that domain in the DB
```

## Limitations

- Firefox only. No Chrome/Chromium support yet.
- Always uses the `Default=1` profile. No way to select a specific profile.
- Requires the browser's cookie DB to be on the local filesystem.

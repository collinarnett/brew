{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.brew.homelab;
  vars = config.clan.core.vars.generators;
in
{
  # Kanidm has no forward-auth endpoint, so oauth2-proxy fills that role
  # for services that rely on the reverse proxy for authentication.
  config = mkIf (cfg.enable && cfg.kanidm.enable) {
    clan.core.vars.generators.oauth2_proxy = {
      # The kanidm provisioner reads the client secret to register it.
      files.oauth2_proxy_client_secret.owner = "kanidm";
      files.oauth2_proxy_cookie_secret = { };
      runtimeInputs = [ pkgs.coreutils ];
      script = ''
        head -c 48 /dev/urandom | base64 --wrap=0 | tr -d '+/=' > "$out"/oauth2_proxy_client_secret
        head -c 32 /dev/urandom | base64 --wrap=0 | tr -- '+/' '-_' > "$out"/oauth2_proxy_cookie_secret
      '';
    };

    services.oauth2-proxy = {
      enable = true;
      provider = "oidc";
      clientID = "forward-auth";
      clientSecretFile = vars.oauth2_proxy.files.oauth2_proxy_client_secret.path;
      oidcIssuerUrl = "https://idm.${cfg.domain}/oauth2/openid/forward-auth";
      httpAddress = "http://127.0.0.1:4180";
      reverseProxy = true;
      trustedProxyIP = [ "127.0.0.1/32" ];
      setXauthrequest = true;
      email.domains = [ "*" ];
      cookie = {
        domain = ".${cfg.domain}";
        secretFile = vars.oauth2_proxy.files.oauth2_proxy_cookie_secret.path;
      };
      extraConfig = {
        whitelist-domain = ".${cfg.domain}";
        code-challenge-method = "S256";
        skip-provider-button = true;
        # Kanidm access tokens live 15 minutes; refreshing the session
        # just before expiry avoids a visible re-auth redirect.
        cookie-refresh = "14m";
        # The session user (X-User to backends) is the short username.
        user-id-claim = "preferred_username";
      };

      # nixpkgs generates the auth_request wiring for these vhosts; the
      # sign-in redirect always round-trips through the domain below, and
      # the wildcard session cookie carries the login to the others.
      nginx = {
        domain = "home.${cfg.domain}";
        virtualHosts = {
          "home.${cfg.domain}" = { };
          "search.${cfg.domain}" = { };
          "grocy.${cfg.domain}" = { };
          "torrents.${cfg.domain}" = { };
        };
      };
    };
  };
}

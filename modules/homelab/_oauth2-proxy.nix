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
      oidcIssuerUrl = "https://idm.trexd.dev/oauth2/openid/forward-auth";
      httpAddress = "http://127.0.0.1:4180";
      reverseProxy = true;
      trustedProxyIP = [ "127.0.0.1/32" ];
      setXauthrequest = true;
      # Traefik's forwardAuth points at the proxy root: authenticated
      # requests hit this static upstream and pass with a 202, while
      # unauthenticated browsers get a real 302 into the sign-in flow
      # (a 401-wrapped redirect from an errors middleware would not be
      # followed by browsers).
      upstream = [ "static://202" ];
      email.domains = [ "*" ];
      cookie = {
        domain = ".trexd.dev";
        secretFile = vars.oauth2_proxy.files.oauth2_proxy_cookie_secret.path;
      };
      extraConfig = {
        whitelist-domain = ".trexd.dev";
        code-challenge-method = "S256";
        skip-provider-button = true;
      };
    };
  };
}

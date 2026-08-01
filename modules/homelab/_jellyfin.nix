{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.brew.homelab;
in
{
  config = mkIf (cfg.enable && cfg.jellyfin.enable) {
    services.jellyfin.enable = true;
    users.users.jellyfin.extraGroups = [ "multimedia" ];

    # Auth handled inside Jellyfin by jellyfin-plugin-sso (OIDC against
    # Kanidm). Every Jellyfin user is pinned to AuthenticationProviderId =
    # Jellyfin.Plugin.SSO_Auth.Api.SSOController, so password login is dead
    # even with the form publicly exposed. Native clients (Finamp audio
    # streams, /socket websocket) need the proxy out of the way.
    services.nginx.virtualHosts."media.${cfg.domain}" = {
      enableACME = true;
      # DNS-01 through the acme defaults; HTTP-01 cannot reach this host.
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
        proxyWebsockets = true;
      };
    };
  };
}

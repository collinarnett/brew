{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.brew.homelab;
in
{
  config = mkIf (cfg.enable && cfg.crowdsec.enable) {
    services.crowdsec = {
      enable = true;
      autoUpdateService = true;
      hub.collections = [
        # Syslog/sshd parsers plus ssh-bruteforce and ssh-slow-bruteforce
        # scenarios.
        "crowdsecurity/linux"
        # Nginx access-log parser plus http probing, path traversal, and
        # CVE-scan scenarios.
        "crowdsecurity/nginx"
      ];
      settings = {
        # Serve the local API so the firewall bouncer can pull ban
        # decisions. 8080 belongs to searx.
        general.api.server = {
          enable = true;
          listen_uri = "127.0.0.1:8081";
        };
        # Credential files are written by cscli at first start
        # (`machine add --auto` / `capi register`), so they must live in
        # the writable, persisted state directory. Registering with the
        # central API pulls the community blocklist of known-bad IPs and
        # shares locally detected attacker IPs back to it.
        lapi.credentialsFile = "/var/lib/crowdsec/lapi.yaml";
        capi.credentialsFile = "/var/lib/crowdsec/capi.yaml";
      };
      localConfig.acquisitions = [
        {
          source = "journalctl";
          journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
          labels.type = "syslog";
        }
        {
          source = "file";
          filenames = [ "/var/log/nginx/*.log" ];
          labels.type = "nginx";
        }
      ];
    };

    # /var/log/nginx is 0750 nginx:nginx; group membership grants read
    # access to the access logs.
    users.users.crowdsec.extraGroups = [ "nginx" ];

    # cscli aborts outright when the configured CAPI credentials file is
    # missing, but `cscli capi register` only writes it as the last step
    # of first-start setup. An empty file passes the load (treated as
    # "not yet registered") and gets filled in by the registration.
    systemd.tmpfiles.rules = [
      "f /var/lib/crowdsec/capi.yaml 0600 crowdsec crowdsec -"
    ];

    # The bouncer register oneshot invokes the package's unwrapped cscli,
    # which reads /etc/crowdsec/config.yaml. The engine's actual config
    # lives in the nix store, so expose the identical generated file at
    # the path cscli expects.
    environment.etc."crowdsec/config.yaml".source =
      (pkgs.formats.yaml { }).generate "crowdsec.yaml"
        config.services.crowdsec.settings.general;

    # The register oneshot lists /var/lib/crowdsec in its StateDirectory.
    # With DynamicUser, systemd migrates such directories into
    # /var/lib/private via rename(), which fails with EXDEV because
    # /var/lib/crowdsec is an impermanence bind mount. The unit already
    # runs as the static crowdsec user, so dynamic allocation adds
    # nothing.
    systemd.services.crowdsec-firewall-bouncer-register.serviceConfig.DynamicUser = lib.mkForce false;

    # Drops packets from IPs the engine has banned. Registers itself
    # against the local API on first start and stores its key under
    # /var/lib/crowdsec-firewall-bouncer-register.
    services.crowdsec-firewall-bouncer.enable = true;

    # The bouncer unit Requires= the register oneshot but declares no
    # After= ordering on it, so on first start the bouncer races the
    # creation of its API key file and fails at LoadCredential
    # (nixpkgs issue #476253).
    systemd.services.crowdsec-firewall-bouncer.after = [
      "crowdsec-firewall-bouncer-register.service"
    ];
  };
}

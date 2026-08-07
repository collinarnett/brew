{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatMapStringsSep
    escapeShellArg
    mkIf
    mkMerge
    removePrefix
    ;
  cfg = config.brew.homelab;

  radHome = "/var/lib/radicle";

  # Base unit for oneshot `rad` CLI runs against the system node. These run
  # outside radicle-node's namespace, so they get the same profile mounts
  # (config, keys) the NixOS module gives the node itself.
  radicleCliUnit = {
    after = [ "radicle-node.service" ];
    wants = [ "radicle-node.service" ];
    environment = {
      HOME = radHome;
      RAD_HOME = radHome;
    };
    path = [
      config.services.radicle.package
      pkgs.gitMinimal
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "radicle";
      Group = "radicle";
      LoadCredential = "radicle_key:${config.clan.core.vars.generators.radicle.files.radicle_key.path}";
      BindReadOnlyPaths = [
        "${config.services.radicle.configFile}:${radHome}/config.json"
        "%d/radicle_key:${radHome}/keys/radicle"
        "${
          pkgs.writeText "radicle.pub" config.clan.core.vars.generators.radicle.files."radicle_key.pub".value
        }:${radHome}/keys/radicle.pub"
      ];
      StateDirectory = "radicle";
      StateDirectoryMode = "0750";
    };
  };
in
{
  config = mkIf (cfg.enable && cfg.radicle.enable) {
    # Node identity: a plain ed25519 SSH keypair, the same thing `rad auth`
    # produces. The private key is loaded into the service via a systemd
    # credential; the public key is committed to vars/ and read at eval time.
    clan.core.vars.generators.radicle = {
      files.radicle_key = { };
      files."radicle_key.pub".secret = false;
      runtimeInputs = [ pkgs.openssh ];
      script = ''
        ssh-keygen -t ed25519 -N "" -C "" -f "$out"/radicle_key
        # rad rejects public keys carrying a comment; keep only type and key.
        pubkey=$(cut -d' ' -f1-2 "$out"/radicle_key.pub)
        printf '%s' "$pubkey" > "$out"/radicle_key.pub
      '';
    };

    services.radicle = {
      enable = true;
      privateKey = config.clan.core.vars.generators.radicle.files.radicle_key.path;
      publicKey = config.clan.core.vars.generators.radicle.files."radicle_key.pub".value;
      settings = {
        node = {
          alias = config.networking.hostName;
          # Seed nothing by default; repositories are opted in through the
          # follow and seedRepositories options (or `sudo rad-system seed`).
          seedingPolicy.default = "block";
        };
        web.pinned.repositories = cfg.radicle.seedRepositories;
      };
      # Peers on the LAN and Yggdrasil mesh dial the node directly on 8776.
      node.openFirewall = true;
      httpd = {
        enable = true;
        listenPort = 8778;
      };
    };

    # Apply follow policies and seed the configured repositories. Policies
    # live in the node's database, not config.json, so they are declared here
    # and converged on every activation.
    systemd.services.radicle-node-setup =
      mkIf (cfg.radicle.follow != [ ] || cfg.radicle.seedRepositories != [ ])
        (mkMerge [
          radicleCliUnit
          {
            description = "Apply Radicle follow policies and seed repositories";
            wantedBy = [ "multi-user.target" ];
            serviceConfig.RemainAfterExit = true;
            script = ''
              for _ in $(seq 30); do
                rad node status >/dev/null 2>&1 && break
                sleep 1
              done
              ${concatMapStringsSep "\n" (did: "rad follow ${escapeShellArg did} || true") cfg.radicle.follow}
              ${concatMapStringsSep "\n" (
                rid: "rad seed ${escapeShellArg rid} --scope all || true"
              ) cfg.radicle.seedRepositories}
            '';
          }
        ]);

    # Followed identities announce new repositories over gossip, but the node
    # only fetches what it already seeds. Sweep their inventories periodically
    # so anything they publish gets seeded without touching this config.
    systemd.services.radicle-auto-seed = mkIf (cfg.radicle.follow != [ ]) (mkMerge [
      radicleCliUnit
      {
        description = "Seed repositories published by followed identities";
        script = concatMapStringsSep "\n" (did: ''
          (rad node inventory --nid ${escapeShellArg (removePrefix "did:key:" did)} || true) \
            | while read -r rid; do
              rad seed "$rid" --scope all || true
            done
        '') cfg.radicle.follow;
      }
    ]);
    systemd.timers.radicle-auto-seed = mkIf (cfg.radicle.follow != [ ]) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "5h";
        RandomizedDelaySec = "10min";
      };
    };

    # The explorer is a static SPA built to query this seed's httpd API at
    # the same origin (/api and /raw go to radicle-httpd). No auth on any
    # of it: radicle-httpd is a read-only API by design, and git/rad
    # clients cannot carry a session cookie.
    services.nginx = {
      enable = true;
      virtualHosts."garden.${cfg.domain}" = {
        enableACME = true;
        # DNS-01 through the acme defaults; HTTP-01 cannot reach this host.
        acmeRoot = null;
        forceSSL = true;
        root = pkgs.radicle-explorer.withConfig {
          preferredSeeds = [
            {
              hostname = "garden.${cfg.domain}";
              port = 443;
              scheme = "https";
            }
          ];
        };
        locations."/".tryFiles = "$uri /index.html";
        locations."^~ /api".proxyPass =
          "http://${config.services.radicle.httpd.listenAddress}:${toString config.services.radicle.httpd.listenPort}";
        locations."^~ /raw".proxyPass =
          "http://${config.services.radicle.httpd.listenAddress}:${toString config.services.radicle.httpd.listenPort}";
        # Seeded repositories clone over git smart HTTP straight from
        # radicle-httpd, which is what lets Nix flake inputs fetch them.
        locations."~ ^/z[a-zA-Z0-9]+\\.git/".proxyPass =
          "http://${config.services.radicle.httpd.listenAddress}:${toString config.services.radicle.httpd.listenPort}";
      };
    };
  };
}

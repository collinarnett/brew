{ ... }:
{
  flake.modules.nixos.recap-timer =
    { config, lib, ... }:
    let
      cfg = config.brew.recap-timer;
    in
    {
      options.brew.recap-timer.enable = lib.mkEnableOption "nightly claude-code /recap timer";
      config = lib.mkIf cfg.enable {
        home-manager.sharedModules = [ { brew.recap-timer.enable = true; } ];
      };
    };

  flake.modules.homeManager.recap-timer =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.recap-timer;
      recapRun = pkgs.writeShellApplication {
        name = "recap-run";
        runtimeInputs = with pkgs; [
          bash
          claude-code
          coreutils
          emacs
          jq
          recap-triage
        ];
        text = ''exec claude -p "/recap yesterday"'';
      };
    in
    {
      options.brew.recap-timer.enable = lib.mkEnableOption "nightly claude-code /recap timer";
      config = lib.mkIf cfg.enable {
        systemd.user.services.recap = {
          Unit = {
            Description = "Nightly Claude Code /recap yesterday";
            After = [
              "emacs.service"
              "graphical-session.target"
            ];
            Wants = [ "emacs.service" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe recapRun;

            ProtectSystem = "strict";
            PrivateTmp = true;
            PrivateDevices = true;
            PrivateMounts = true;

            NoNewPrivileges = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHostname = true;
            ProtectProc = "invisible";
            LockPersonality = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            RestrictNamespaces = true;
            RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";
            SystemCallArchitectures = "native";
            SystemCallFilter = [
              "@system-service"
              "~@privileged"
            ];
            CapabilityBoundingSet = "";
            AmbientCapabilities = "";
          };
        };

        systemd.user.timers.recap = {
          Unit.Description = "Nightly Claude Code /recap trigger";
          Timer = {
            OnCalendar = "*-*-* 11:00:00";
            Persistent = true;
            Unit = "recap.service";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}

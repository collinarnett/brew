{ ... }:
{
  flake.nixosModules.whisperlivekit =
    {
      config,
      lib,
      pkgs,
      utils,
      ...
    }:
    let
      cfg = config.brew.whisperlivekit;
    in
    {
      options.brew.whisperlivekit = {
        enable = lib.mkEnableOption "WhisperLiveKit real-time speech-to-text server";

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.whisperlivekit;
          defaultText = lib.literalExpression "pkgs.whisperlivekit";
          description = ''
            The WhisperLiveKit package to use.
            Set to `pkgs.whisperlivekit-cuda` for NVIDIA GPU acceleration.
          '';
        };

        model = lib.mkOption {
          type = lib.types.str;
          default = "base";
          description = "Whisper model size (e.g. tiny, base, small, medium, large-v3).";
        };

        backend = lib.mkOption {
          type = lib.types.enum [
            "faster-whisper"
            "whisper"
            "auto"
          ];
          default = "faster-whisper";
          description = "Speech recognition backend.";
        };

        host = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "Address to bind the server to.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8000;
          description = "Port the server listens on.";
        };

        language = lib.mkOption {
          type = lib.types.str;
          default = "auto";
          description = "Source language for transcription (or auto for detection).";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to open the firewall for the server port.";
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Extra command-line arguments passed to the server.";
        };
      };

      config = lib.mkIf cfg.enable {
        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

        systemd.services.whisperlivekit = {
          description = "WhisperLiveKit speech-to-text server";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];

          environment = {
            HOME = "/var/lib/whisperlivekit";
            HF_HOME = "/var/lib/whisperlivekit/hf_home";
          };

          serviceConfig = {
            ExecStart = utils.escapeSystemdExecArgs (
              [
                (lib.getExe cfg.package)
                "--host"
                cfg.host
                "--port"
                (toString cfg.port)
                "--backend"
                cfg.backend
                "--model"
                cfg.model
                "--language"
                cfg.language
              ]
              ++ cfg.extraArgs
            );

            DynamicUser = true;
            StateDirectory = "whisperlivekit";
            CacheDirectory = "whisperlivekit";
            WorkingDirectory = "/var/lib/whisperlivekit";

            Restart = "on-failure";
            RestartSec = 10;

            # Device access — use character device classes (not specific paths)
            # so any number of GPUs is covered automatically.
            # These are harmless on systems without NVIDIA hardware.
            PrivateDevices = false;
            DevicePolicy = "closed";
            DeviceAllow = [
              # https://docs.nvidia.com/dgx/pdf/dgx-os-5-user-guide.pdf
              "char-nvidiactl"
              "char-nvidia-caps"
              "char-nvidia-frontend"
              "char-nvidia-uvm"
            ];

            # Sandboxing
            CapabilityBoundingSet = "";
            LockPersonality = true;
            MemoryDenyWriteExecute = false; # numba/llvmlite requires JIT
            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateUsers = true;
            ProcSubset = "all";
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            ProtectSystem = "strict";
            RemoveIPC = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = [
              "@system-service"
              "~@privileged"
            ];
            UMask = "0077";
          };
        };
      };
    };
}

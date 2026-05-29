{ ... }:
{
  flake.modules.nixos.ollama =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.brew.ollama;
    in
    {
      options.brew.ollama = {
        enable = lib.mkEnableOption "ollama";
        models = lib.mkOption {
          type = lib.types.attrsOf lib.types.package;
          default = { };
          example = lib.literalExpression ''
            {
              "gpt-oss-heretic-ara-v4:20b" = pkgs.gpt-oss-20b-heretic-ara-v4;
            }
          '';
          description = ''
            Map of ollama tag → Modelfile derivation. Each entry is
            registered with `ollama create <tag> -f <modelfile>` by a
            one-shot systemd service. Per-tag sentinel makes activation
            idempotent.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        services.ollama.enable = true;

        systemd.services.ollama-register-models = lib.mkIf (cfg.models != { }) {
          description = "Register custom Modelfiles with ollama";

          wantedBy = [ "multi-user.target" ];
          after = [ "ollama.service" ];
          requires = [ "ollama.service" ];

          path = [ config.services.ollama.package ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "ollama";
            Group = "ollama";
            StateDirectory = "ollama-register";
            # ollama CLI writes to $HOME/.ollama/; the `ollama` system
            # user's pw_dir is /var/empty, so point HOME at the StateDirectory.
            Environment = [ "HOME=%S/ollama-register" ];
          };

          script = ''
            set -euo pipefail
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (tag: modelfile: ''
                if ollama show ${lib.escapeShellArg tag} >/dev/null 2>&1; then
                  echo ${lib.escapeShellArg "${tag} already registered"}
                else
                  ollama create ${lib.escapeShellArg tag} -f ${modelfile}
                fi
              '') cfg.models
            )}
          '';
        };
      };
    };
}

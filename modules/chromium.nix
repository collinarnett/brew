{ ... }:
{
  flake.nixosModules.chromium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.chromium;
    in
    {
      options.brew.chromium = {
        enable = lib.mkEnableOption "Chromium browser with WhisperLiveKit extension";

        whisperlivekit.serverUrl = lib.mkOption {
          type = lib.types.str;
          description = "WebSocket URL for the WhisperLiveKit server.";
          example = "ws://vampire:8010/asr";
        };
      };

      config = lib.mkIf cfg.enable {
        programs.chromium.extraOpts."3rdparty".extensions.${pkgs.whisperlivekit-chrome-extension.extensionId} = {
          websocketUrl = cfg.whisperlivekit.serverUrl;
        };

        home-manager.sharedModules = [
          {
            programs.chromium = {
              enable = true;
              extensions = [
                {
                  id = pkgs.whisperlivekit-chrome-extension.extensionId;
                  crxPath = "${pkgs.whisperlivekit-chrome-extension}/whisperlivekit.crx";
                  version = pkgs.whisperlivekit-chrome-extension.version;
                }
              ];
            };
          }
        ];
      };
    };
}

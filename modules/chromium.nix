{ ... }:
let
  chromiumOptions =
    { lib, ... }:
    {
      options.brew.chromium = {
        enable = lib.mkEnableOption "Chromium browser with WhisperLiveKit extension";
        whisperlivekit.serverUrl = lib.mkOption {
          type = lib.types.str;
          description = "WebSocket URL for the WhisperLiveKit server.";
          example = "ws://vampire:8010/asr";
        };
      };
    };
in
{
  flake.modules.nixos.chromium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.chromium;
      ext = pkgs.whisperlivekit-chrome-extension;

      # Chromium on Linux ignores ~/.config/chromium/External Extensions/
      # (home-manager's crxPath target); it only reads external extension
      # JSON from <binary-dir>/extensions/, which is read-only in the nix
      # store.  Use ExtensionInstallForcelist with a local update manifest
      # instead — Chromium's supported enterprise side-loading mechanism.
      updateManifest = pkgs.writeText "whisperlivekit-update-manifest.xml" ''
        <?xml version='1.0' encoding='UTF-8'?>
        <gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
          <app appid='${ext.extensionId}'>
            <updatecheck codebase='file://${ext}/whisperlivekit.crx' version='${ext.version}' />
          </app>
        </gupdate>
      '';
    in
    {
      imports = [ chromiumOptions ];
      config = lib.mkIf cfg.enable {
        programs.chromium = {
          enable = true;
          extensions = [
            "${ext.extensionId};file://${updateManifest}"
          ];
          extraOpts = {
            "3rdparty".extensions.${ext.extensionId} = {
              websocketUrl = cfg.whisperlivekit.serverUrl;
            };
            AudioCaptureAllowedUrls = [
              "chrome-extension://${ext.extensionId}"
            ];
          };
        };

        home-manager.sharedModules = [
          { brew.chromium.enable = true; }
        ];
      };
    };

  flake.modules.homeManager.chromium =
    { config, lib, ... }:
    let
      cfg = config.brew.chromium;
    in
    {
      options.brew.chromium.enable = lib.mkEnableOption "Chromium browser";
      config = lib.mkIf cfg.enable {
        programs.chromium.enable = true;
      };
    };
}

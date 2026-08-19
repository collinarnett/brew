{ ... }:
let
  # Both halves of this module install Firefox, and the home-manager profile
  # precedes the system one in PATH. They have to be the same derivation or the
  # browser that actually launches is the one without a CDM.
  withWidevine =
    pkgs:
    pkgs.firefox-esr.overrideAttrs (old: {
      buildCommand = old.buildCommand + ''
        wrapProgram $out/bin/firefox-esr \
          --set MOZ_GMP_PATH ${pkgs.widevine-firefox}/gmp-widevinecdm/system-installed
      '';
    });
in
{
  flake.modules.nixos.firefox =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.firefox;
    in
    {
      options.brew.firefox.enable = lib.mkEnableOption "firefox";
      config = lib.mkIf cfg.enable {
        programs.firefox.enable = true;
        # Firefox ships no Widevine CDM; left alone it downloads one from Google
        # into the profile, where its version is untracked and survives rebuilds.
        # MOZ_GMP_PATH is the only interface for supplying one, so the CDM comes
        # from the store and moves with flake.lock like every other package.
        #
        # Set on the binary rather than the session: a session variable reaches
        # only processes started after the next login, leaving the browser from
        # the current session without a CDM.
        programs.firefox.package = withWidevine pkgs;

        # Locked rather than default: a user.js in the profile outranks a default
        # pref, and these decide whether DRM and extension updates work at all.
        programs.firefox.preferences = {
          "media.gmp-widevinecdm.version" = "system-installed";
          "media.gmp-widevinecdm.visible" = true;
          "media.gmp-widevinecdm.enabled" = true;
          "media.gmp-widevinecdm.autoupdate" = false;
          "media.gmp-manager.updateEnabled" = false;
          "media.eme.enabled" = true;
          "extensions.update.enabled" = false;
        };

        programs.firefox.policies = {
          ExtensionSettings = {
            # Bypass Paywalls Clean — self-distributed signed XPI from gitflic,
            # force-installed from its nix store path (see pkgs/bypass-paywalls-clean.nix).
            "magnolia@12.34" = {
              install_url = "file://${pkgs.bypass-paywalls-clean}";
              installation_mode = "force_installed";
            };
          };
          SearchEngines = {
            Default = "SearX";
            Remove = [
              "Google"
              "Bing"
              "Amazon.com"
              "eBay"
              "Wikipedia"
            ];
            Add = [
              {
                Name = "SearX";
                URLTemplate = "https://search.trexd.dev/search?q={searchTerms}";
                Method = "GET";
                IconURL = "https://search.trexd.dev/favicon.ico";
                SuggestURLTemplate = "https://search.trexd.dev/autocompleter?q={searchTerms}";
              }
            ];
          };
        };
        home-manager.sharedModules = [
          { brew.firefox.enable = true; }
        ];
      };
    };

  flake.modules.homeManager.firefox =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.firefox;
    in
    {
      options.brew.firefox.enable = lib.mkEnableOption "firefox";
      config = lib.mkIf cfg.enable {
        home.packages = [ (withWidevine pkgs) ];
      };
    };
}

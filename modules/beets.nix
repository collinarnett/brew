{ ... }:
{
  flake.modules.nixos.beets =
    { config, lib, ... }:
    let
      cfg = config.brew.beets;
    in
    {
      options.brew.beets.enable = lib.mkEnableOption "beets";
      config = lib.mkIf cfg.enable {
        # TODO: Remove overlay once nixpkgs#493540 is resolved (autodocsumm vs sphinx 9)
        nixpkgs.overlays = [
          (final: prev: {
            beets = prev.beets.overridePythonAttrs (old: {
              outputs = [ "out" ];
              nativeBuildInputs = builtins.filter (
                dep: !(lib.hasInfix "sphinx" (lib.toLower (dep.pname or dep.name or "")))
              ) (old.nativeBuildInputs or [ ]);
            });
          })
        ];
        home-manager.sharedModules = [
          { brew.beets.enable = true; }
        ];
      };
    };

  flake.modules.homeManager.beets =
    { config, lib, ... }:
    let
      cfg = config.brew.beets;
    in
    {
      options.brew.beets.enable = lib.mkEnableOption "beets";
      config = lib.mkIf cfg.enable {
        programs.beets = {
          enable = true;
          settings = {
            directory = "/media/music/";
            plugins = [
              "fetchart"
              "musicbrainz"
            ];
          };
        };
      };
    };
}

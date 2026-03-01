{ ... }:
{
  flake.nixosModules.beets =
    { config, lib, ... }:
    let
      cfg = config.brew.beets;
      user = config.brew.user;
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
        home-manager.users.${user} = {
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
    };
}

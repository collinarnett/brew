{ ... }:
{
  flake.nixosModules.obs-studio =
    { config, lib, ... }:
    {
      options.brew.obs-studio.enable = lib.mkEnableOption "obs-studio";
      config = lib.mkIf config.brew.obs-studio.enable {
        programs.obs-studio = {
          enable = true;
          enableVirtualCamera = true;
        };
      };
    };
}

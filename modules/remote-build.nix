{ config, lib, ... }:
let
  cfg = config.brew.remote-build;
in
{
  options.brew.remote-build.enable = lib.mkEnableOption "remote-build";
  config = lib.mkIf cfg.enable {
    users.users.remotebuild = {
      isNormalUser = true;
      createHome = false;
      group = "remotebuild";
      openssh.authorizedKeys.keyFiles = [ ./../secrets/keys/remotebuild.pub ];
    };

    users.groups.remotebuild = { };

    nix.settings.trusted-users = [ "remotebuild" ];
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.brew.gpg-agent;
  user = config.brew.user;
in
{
  options.brew.gpg-agent.enable = lib.mkEnableOption "gpg-agent" // {
    default = true;
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      services.gpg-agent = {
        enable = true;
        pinentry.package = pkgs.pinentry-all;
        extraConfig = ''
          allow-emacs-pinentry
          allow-loopback-pinentry
        '';
      };
    };
  };
}

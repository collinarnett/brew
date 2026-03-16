{ ... }:
{
  flake.modules.homeManager.gpg-agent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.gpg-agent;
    in
    {
      options.brew.gpg-agent.enable = lib.mkEnableOption "gpg-agent";
      config = lib.mkIf cfg.enable {
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

{ ... }:
{
  flake.nixosModules.common =
    { config, lib, ... }:
    let
      cfg = config.brew.common;
    in
    {
      options.brew.common.enable = lib.mkEnableOption "common profile";
      config = lib.mkIf cfg.enable {
        brew = {
          autojump.enable = true;
          bat.enable = true;
          btop.enable = true;
          direnv.enable = true;
          fzf.enable = true;
          gh.enable = true;
          git.enable = true;
          gpg.enable = true;
          gpg-agent.enable = true;
          keychain.enable = true;
          starship.enable = true;
          zoxide.enable = true;
          zsh.enable = true;
        };
      };
    };
}

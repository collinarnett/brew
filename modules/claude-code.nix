{ ... }:
{
  flake.nixosModules.claude-code =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.claude-code;
    in
    {
      options.brew.claude-code = {
        enable = lib.mkEnableOption "Claude Code CLI";
      };

      config = lib.mkIf cfg.enable {
        home-manager.sharedModules = [
          {
            programs.claude-code = {
              enable = true;
              settings = {
                alwaysThinkingEnabled = true;
              };
              skillsDir = ../configurations/claude-code/skills;
            };
          }
        ];
      };
    };
}

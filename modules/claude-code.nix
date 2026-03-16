{ ... }:
{
  flake.modules.nixos.claude-code =
    {
      config,
      lib,
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
          { brew.claude-code.enable = true; }
        ];
      };
    };

  flake.modules.homeManager.claude-code =
    {
      config,
      lib,
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
        programs.claude-code = {
          enable = true;
          settings = {
            alwaysThinkingEnabled = true;
            permissions.allow = [
              # Web
              "WebSearch"
              "WebFetch(domain:raw.githubusercontent.com)"
              "WebFetch(domain:github.com)"
              "WebFetch(domain:discourse.nixos.org)"
              "WebFetch(domain:hackage.haskell.org)"
              "WebFetch(domain:flake.parts)"
              "WebFetch(domain:pyproject-nix.github.io)"
              "WebFetch(domain:inside.java)"
              "WebFetch(domain:wiki.openjdk.org)"
              "WebFetch(domain:bugs.openjdk.org)"
              "WebFetch(domain:gvolpe.com)"
              "WebFetch(domain:greenfield.blog)"
              "WebFetch(domain:thurs.dev)"
              "WebFetch(domain:firefox-source-docs.mozilla.org)"
              "WebFetch(domain:searchfox.org)"
              "WebFetch(domain:cat-in-136.github.io)"
              "WebFetch(domain:intoli.com)"
              "WebFetch(domain:bugzilla.mozilla.org)"

              # Read-only system inspection
              "Bash(ls:*)"
              "Bash(find:*)"
              "Bash(grep:*)"
              "Bash(wc:*)"
              "Bash(sort:*)"
              "Bash(echo:*)"
              "Bash(ps:*)"
              "Bash(top:*)"
              "Bash(ss:*)"
              "Bash(mount:*)"
              "Bash(lsusb:*)"
              "Bash(dmesg:*)"
              "Bash(command:*)"
              "Bash(journalctl:*)"
              "Bash(systemctl status:*)"
              "Bash(systemctl list-timers:*)"
              "Bash(systemctl --user list-timers:*)"
              "Bash(crontab:*)"
              "Bash(sudo crontab:*)"
              "Bash(docker ps:*)"
              "Bash(docker stats:*)"
              "Bash(virsh list:*)"
              "Bash(sudo virsh:*)"

              # Dev tools
              "Bash(gh api:*)"
              "Bash(curl:*)"
              "Bash(python3:*)"
              "Bash(emacs:*)"
              "Bash(nix develop:*)"
              "Bash(nix-prefetch-git:*)"
              "Bash(nix-prefetch-url:*)"
            ];
          };
          skillsDir = ../configurations/claude-code/skills;
        };
      };
    };
}

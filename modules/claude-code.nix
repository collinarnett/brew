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
          {
            brew.claude-code.enable = true;
            brew.claude-code.ghTokenFile = lib.mkIf config.brew.gh-token.enable
              config.clan.core.vars.generators.gh_token.files.gh_token.path;
          }
        ];
      };
    };

  flake.modules.homeManager.claude-code =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.claude-code;

      # A .hlint.yaml at the repository root marks a project that has opted
      # into the Haskell baseline: restricted partial functions, ormolu
      # formatting, warnings as errors. Projects without one are left alone.
      lintEditedHaskell = pkgs.writeShellApplication {
        name = "claude-lint-edited-haskell";
        runtimeInputs = with pkgs; [
          git
          hlint
          jq
        ];
        text = ''
          file=$(jq -r '.tool_input.file_path // empty')
          case "$file" in
            *.hs) ;;
            *) exit 0 ;;
          esac
          [ -f "$file" ] || exit 0

          root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null) || exit 0
          [ -f "$root/.hlint.yaml" ] || exit 0

          cd "$root"
          if ! output=$(hlint "$file" 2>&1); then
            printf '%s\n' "$output" >&2
            exit 2
          fi
        '';
      };

      # Sweeps every Haskell file the working tree has touched, so a violation
      # in a file edited earlier in the session cannot survive to the end of
      # the turn. Compilation is deliberately absent: these projects take
      # minutes to hours to build, and the build gate lives in pre-commit.
      gateChangedHaskell = pkgs.writeShellApplication {
        name = "claude-gate-changed-haskell";
        runtimeInputs = with pkgs; [
          git
          hlint
          jq
          ormolu
        ];
        text = ''
          # Claude Code sets this once it has already been blocked once, and
          # honouring it is what keeps a failing gate from looping forever.
          if [ "$(jq -r '.stop_hook_active // false')" = "true" ]; then
            exit 0
          fi

          root=$(git -C "''${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
          [ -f "$root/.hlint.yaml" ] || exit 0
          cd "$root"

          mapfile -t files < <(
            {
              git diff --name-only --diff-filter=d HEAD -- '*.hs'
              git ls-files --others --exclude-standard -- '*.hs'
            } | sort -u
          )
          [ ''${#files[@]} -gt 0 ] || exit 0

          status=0
          failures=""
          for f in "''${files[@]}"; do
            [ -f "$f" ] || continue
            if ! out=$(hlint "$f" 2>&1); then
              failures+="$out"$'\n'
              status=2
            fi
            if ! out=$(ormolu --mode check "$f" 2>&1); then
              failures+="$f is not ormolu-formatted; run ormolu --mode inplace on it"$'\n'
              status=2
            fi
          done

          if [ "$status" -ne 0 ]; then
            printf '%s' "$failures" >&2
            exit 2
          fi
        '';
      };
    in
    {
      options.brew.claude-code = {
        enable = lib.mkEnableOption "Claude Code CLI";
        ghTokenFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to file containing GitHub personal access token";
        };
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.recap-triage ];
        programs.mcp.enable = true;
        mcp-servers.programs = {
          nixos.enable = true;
          git.enable = true;
          github = {
            enable = true;
            passwordCommand = lib.mkIf (cfg.ghTokenFile != null) {
              GITHUB_PERSONAL_ACCESS_TOKEN = [
                "cat"
                cfg.ghTokenFile
              ];
            };
          };
        };
        programs.mcp.servers = {
          clan.command = lib.getExe pkgs.clan-mcp-wrapped;
          gitlab.command = lib.getExe pkgs.gitlab-mcp;
        };
        programs.claude-code = {
          enable = true;
          enableMcpIntegration = true;
          settings = {
            alwaysThinkingEnabled = true;
            hooks = {
              PostToolUse = [
                {
                  matcher = "Edit|MultiEdit|Write";
                  hooks = [
                    {
                      type = "command";
                      command = lib.getExe lintEditedHaskell;
                    }
                  ];
                }
              ];
              Stop = [
                {
                  hooks = [
                    {
                      type = "command";
                      command = lib.getExe gateChangedHaskell;
                    }
                  ];
                }
              ];
            };
            permissions.defaultMode = "auto";
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
          memory.source = ../configurations/claude-code/CLAUDE.md;
          skills = builtins.mapAttrs
            (name: _: ../configurations/claude-code/skills/${name})
            (builtins.readDir ../configurations/claude-code/skills);
        };
      };
    };
}

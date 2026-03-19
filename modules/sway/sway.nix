{ ... }:
let
  startupAppOptions = { lib, ... }: {
    options = {
      command = lib.mkOption {
        type = lib.types.str;
        description = "Command to launch";
      };
      waitFor = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "App ID or class pattern to wait for before continuing to next app";
      };
      terminal = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Wrap command in kitty terminal";
      };
      requiresInternet = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Skip this app if no internet connectivity";
      };
      noAssign = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Move window back to this workspace after launch (overrides conflicting assign rules)";
      };
    };
  };

  workspaceOptions = { lib, ... }: {
    options = {
      output = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Output to assign this workspace to";
      };
      assigns = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [ ];
        description = "Window criteria that permanently route to this workspace";
      };
      startup = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule startupAppOptions);
        default = [ ];
        description = "Apps to launch on this workspace at startup";
      };
    };
  };

  swayOptions =
    { lib, ... }:
    {
      options.brew.sway = {
        enable = lib.mkEnableOption "sway";
        modifier = lib.mkOption {
          type = lib.types.str;
          default = "Mod4";
          description = "Modifier key (Mod1 for Alt, Mod4 for Super)";
        };
        outputs = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Sway output configuration per host";
        };
        workspaces = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule workspaceOptions);
          default = { };
          description = "Per-workspace configuration: output binding, window assigns, and startup apps";
        };
        focusWorkspace = lib.mkOption {
          type = lib.types.str;
          default = "1";
          description = "Workspace to focus after startup completes";
        };
        extraConfig = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Extra sway config lines per host";
        };
      };
    };
in
{
  flake.modules.nixos.sway =
    { config, lib, ... }:
    let
      cfg = config.brew.sway;
    in
    {
      imports = [ swayOptions ];
      config = lib.mkIf cfg.enable {
        programs.sway.enable = true;
        security.pam.services.swaylock = { };
        home-manager.sharedModules = [
          {
            brew.sway = {
              enable = true;
              inherit (cfg)
                modifier
                outputs
                workspaces
                focusWorkspace
                extraConfig
                ;
            };
          }
        ];
      };
    };

  flake.modules.homeManager.sway =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.sway;

      # Derive workspaceOutputAssign from workspaces
      workspaceOutputAssign = lib.pipe cfg.workspaces [
        (lib.filterAttrs (_: ws: ws.output != null))
        (lib.mapAttrsToList (name: ws: {
          workspace = name;
          output = ws.output;
        }))
      ];

      # Derive assigns from workspaces
      assigns = lib.pipe cfg.workspaces [
        (lib.filterAttrs (_: ws: ws.assigns != [ ]))
        (lib.mapAttrs (_: ws: ws.assigns))
      ];

      # Collect workspaces with startup apps, sorted by name
      startupWorkspaces = lib.pipe cfg.workspaces [
        (lib.filterAttrs (_: ws: ws.startup != [ ]))
        (lib.mapAttrsToList (name: ws: {
          inherit name;
          inherit (ws) startup;
        }))
        (lib.sort (a: b: a.name < b.name))
      ];

      hasInternetApps = lib.any
        (ws: lib.any (app: app.requiresInternet) ws.startup)
        (lib.attrValues cfg.workspaces);

      swaymsg = "${pkgs.sway}/bin/swaymsg";
      jq = "${pkgs.jq}/bin/jq";
      ping = "${pkgs.iputils}/bin/ping";
      kitty = "${pkgs.kitty}/bin/kitty";

      # Helper script that waits for a window matching a pattern via sway IPC
      waitForWindow = pkgs.writeShellScript "sway-wait-for-window" ''
        PATTERN="$1"
        TIMEOUT="''${2:-30}"
        timeout "$TIMEOUT" bash -c "
          ${swaymsg} -t subscribe -m '[\"window\"]' | while read -r event; do
            change=\$(echo \"\$event\" | ${jq} -r '.change // empty')
            [ \"\$change\" = \"new\" ] || continue
            app_id=\$(echo \"\$event\" | ${jq} -r '.container.app_id // empty')
            wclass=\$(echo \"\$event\" | ${jq} -r '.container.window_properties.class // empty')
            if echo \"\$app_id \$wclass\" | grep -qiE \"$PATTERN\"; then
              exit 0
            fi
          done
        " || echo "Timed out waiting for $PATTERN"
      '';

      mkLaunchBlock = wsName: app:
        let
          cmd =
            if app.terminal then
              "${kitty} sh -c '${app.command}; exec $SHELL'"
            else
              app.command;
        in
        ''
          # Workspace ${wsName}: ${app.command}
          ${swaymsg} 'workspace number ${wsName}'
        ''
        + lib.optionalString app.requiresInternet ''
          if [ "$HAS_INTERNET" = "1" ]; then
        ''
        + ''
          ${cmd} &
        ''
        + lib.optionalString (app.waitFor != null) ''
          ${waitForWindow} '${app.waitFor}' 30
        ''
        + lib.optionalString app.noAssign ''
          sleep 0.2
          ${swaymsg} '[app_id="${app.waitFor}"] move to workspace number ${wsName}' 2>/dev/null || \
          ${swaymsg} '[class="${app.waitFor}"] move to workspace number ${wsName}' 2>/dev/null || true
        ''
        + lib.optionalString app.requiresInternet ''
          else
            echo "Skipping ${app.command} (no internet)"
          fi
        '';

      startupScript = pkgs.writeShellScript "sway-startup" (
        lib.optionalString hasInternetApps ''

          # Check internet connectivity
          HAS_INTERNET=0
          if (${ping} -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || \
              ${ping} -c 1 -W 2 1.1.1.1 >/dev/null 2>&1); then
            HAS_INTERNET=1
          fi
        ''
        + ''

          # Wait for sway IPC to be ready
          for i in $(seq 1 10); do
            ${swaymsg} -t get_tree >/dev/null 2>&1 && break
            sleep 0.5
          done

          # Pre-create all workspaces on correct outputs
        ''
        + lib.concatStringsSep "" (
          lib.mapAttrsToList (
            name: ws:
            lib.optionalString (ws.output != null) ''
              ${swaymsg} 'workspace number ${name}'
            ''
          ) cfg.workspaces
        )
        + ''

          # Launch startup apps
        ''
        + lib.concatStringsSep "\n" (
          lib.concatMap (
            wsInfo: map (mkLaunchBlock wsInfo.name) wsInfo.startup
          ) startupWorkspaces
        )
        + ''

          # Focus final workspace
          ${swaymsg} 'workspace number ${cfg.focusWorkspace}'
        ''
      );
    in
    {
      imports = [ swayOptions ];
      config = lib.mkIf cfg.enable {
        home.packages = with pkgs; [
          emacs-all-the-icons-fonts
          fira-code
          fira-code-symbols
          siji
          noto-fonts-color-emoji
          ipafont
          liberation_ttf
        ];
        fonts.fontconfig.enable = true;

        wayland.windowManager.sway = {
          enable = true;
          checkConfig = false;
          wrapperFeatures.gtk = true;
          wrapperFeatures.base = true;
          systemd.variables = [ "--all" ];
          config = {
            terminal = "kitty";
            output = cfg.outputs;
            modifier = cfg.modifier;
            bars = [ { command = "${pkgs.waybar}/bin/waybar"; } ];
            workspaceOutputAssign = workspaceOutputAssign;
            assigns = assigns;
            startup = [ { command = "${startupScript}"; } ];
            colors = {
              focused = {
                background = "#6272A4";
                border = "#6272A4";
                childBorder = "#6272A4";
                indicator = "#6272A4";
                text = "#F8F8F2";
              };
              focusedInactive = {
                background = "#44475A";
                border = "#44475A";
                childBorder = "#44475A";
                indicator = "#44475A";
                text = "#F8F8F2";
              };
              unfocused = {
                background = "#282A36";
                border = "#282A36";
                childBorder = "#282A36";
                indicator = "#282A36";
                text = "#BFBFBF";
              };
              urgent = {
                background = "#FF5555";
                border = "#44475A";
                childBorder = "#FF5555";
                indicator = "#FF5555";
                text = "#F8F8F2";
              };
              placeholder = {
                background = "#282A36";
                border = "#282A36";
                childBorder = "#282A36";
                indicator = "#282A36";
                text = "#F8F8F2";
              };
              background = "#F8F8F2";
            };
            window.titlebar = false;
            menu = "${pkgs.wofi}/bin/wofi";
          };
          extraConfig =
            ''
              set $mod ${cfg.modifier}
              bindsym XF86AudioRaiseVolume exec pactl set-sink-volume @DEFAULT_SINK@ +5%
              bindsym XF86AudioLowerVolume exec pactl set-sink-volume @DEFAULT_SINK@ -5%
              bindsym XF86AudioMute exec pactl set-sink-mute @DEFAULT_SINK@ toggle
              bindsym XF86AudioPlay exec playerctl play-pause
              bindsym XF86AudioNext exec playerctl next
              bindsym XF86AudioPrev exec playerctl previous
              bindsym $mod+p exec ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp -d)" - | ${pkgs.wl-clipboard}/bin/wl-copy -t image/png
            ''
            + cfg.extraConfig;
        };
      };
    };
}

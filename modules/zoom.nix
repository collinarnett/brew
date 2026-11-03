{ ... }:
{
  flake.modules.nixos.zoom =
    { config, lib, ... }:
    let
      cfg = config.brew.zoom;
    in
    {
      options.brew.zoom.enable = lib.mkEnableOption "zoom";
      config = lib.mkIf cfg.enable {
        programs.zoom-us.enable = true;
        home-manager.sharedModules = [
          { brew.zoom.enable = true; }
        ];
      };
    };

  flake.modules.homeManager.zoom =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.zoom;
      renderValue = value: if lib.isBool value then lib.boolToString value else toString value;
      enforceSettings = lib.concatStrings (
        lib.mapAttrsToList (
          section: keys:
          lib.concatStrings (
            lib.mapAttrsToList (key: value: ''
              $DRY_RUN_CMD ${pkgs.crudini}/bin/crudini --set "$CONF" ${lib.escapeShellArg section} ${lib.escapeShellArg key} ${lib.escapeShellArg (renderValue value)}
            '') keys
          )
        ) cfg.settings
      );
      # Zoom hides its main window to the tray on close, and a second launch
      # only hands off to the hidden instance without showing it. This
      # launcher shadows the system `zoom` on PATH (the desktop entry runs
      # `zoom %U`): with no arguments and a running Zoom tray item, it
      # activates that item, which is what clicking the tray icon does.
      # Arguments are meeting URLs and always go to the real client.
      launcher = pkgs.writeShellApplication {
        name = "zoom";
        runtimeInputs = with pkgs; [
          jq
          systemd
        ];
        text = ''
          watcher=(org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.kde.StatusNotifierWatcher)
          if [ "$#" -eq 0 ] && busctl --user status "''${watcher[0]}" >/dev/null 2>&1; then
            items=$(busctl --user --json=short get-property "''${watcher[@]}" RegisteredStatusNotifierItems | jq -r '.data[]')
            for item in $items; do
              service=''${item%%/*}
              path=/StatusNotifierItem
              [ "$service" != "$item" ] && path=/''${item#*/}
              id=$(busctl --user --json=short get-property "$service" "$path" org.kde.StatusNotifierItem Id | jq -r .data) || continue
              if [ "$id" = zoom ]; then
                exec busctl --user call "$service" "$path" org.kde.StatusNotifierItem Activate ii 0 0
              fi
            done
          fi
          exec /run/current-system/sw/bin/zoom "$@"
        '';
      };
    in
    {
      options.brew.zoom = {
        enable = lib.mkEnableOption "zoom";
        settings = lib.mkOption {
          type =
            with lib.types;
            attrsOf (
              attrsOf (oneOf [
                bool
                int
                str
              ])
            );
          default = {
            General = {
              enableWaylandShare = true;
              xwayland = false;
            };
          };
          description = ''
            Settings enforced in zoomus.conf, grouped by INI section. Zoom
            rewrites this file at runtime, so the keys are merged into the
            writable file on every activation rather than symlinked from the
            store. The defaults run the client Wayland-native and share the
            screen through the PipeWire portal; under XWayland, Zoom falls
            back to X11 capture, which cannot see native Wayland surfaces on
            sway and shares a single frozen frame.
          '';
        };
      };
      config = lib.mkIf cfg.enable {
        home.packages = [ launcher ];
        home.activation.zoomusConf = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          CONF=${lib.escapeShellArg "${config.xdg.configHome}/zoomus.conf"}
          ${enforceSettings}
        '';
      };
    };
}

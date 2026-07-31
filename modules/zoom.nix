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
        home.activation.zoomusConf = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          CONF=${lib.escapeShellArg "${config.xdg.configHome}/zoomus.conf"}
          ${enforceSettings}
        '';
      };
    };
}

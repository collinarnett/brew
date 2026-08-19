{ ... }:
{
  flake.modules.homeManager.tangaria =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.tangaria;

      # The client stores every value as a string and reads flags back through
      # atoi, so a bool has to reach the file as 1 or 0. Rendered as "true" it
      # parses as 0 and the setting silently inverts.
      renderValue = value: if lib.isBool value then (if value then "1" else "0") else toString value;

      configFile = pkgs.writeText "pwmangclient.ini" (
        lib.generators.toINI { mkKeyValue = key: value: "${key}=${renderValue value}"; } cfg.settings
      );

      configPath = "${config.xdg.configHome}/tangaria/pwmangclient.ini";

      # conf_init resolves --config before $HOME/.pwmangrc, and the path it
      # settles on is also the one conf_save writes back to. clia_find compares
      # the whole token after the dashes against the key, so the value has to be
      # a separate argument; --config=PATH does not match. Flags precede "$@"
      # because the client reads a trailing positional as the server hostname.
      client = pkgs.symlinkJoin {
        name = "tangaria-${pkgs.tangaria.version}";
        paths = [ pkgs.tangaria ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          rm $out/bin/pwmangclient
          makeWrapper ${pkgs.tangaria}/bin/pwmangclient $out/bin/pwmangclient \
            --add-flags "--config ${configPath}"
        '';
      };
    in
    {
      options.brew.tangaria = {
        enable = lib.mkEnableOption "tangaria";

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
          default = { };
          example = lib.literalExpression ''
            {
              MAngband.nick = "collin";
              Angband.TileWidth = 2;
            }
          '';
          description = ''
            Contents of the client's INI file, one attribute set per section.
            Booleans are written as 1 and 0.

            The recognised keys are the conf_get_int and conf_get_string call
            sites in src/client; upstream publishes no schema. The [Term-N]
            sections belong to the Windows build and have no effect here.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Upstream's own defaults, from conf_default_save. "host" is left unset
        # so the client offers the server list instead of dialling one directly.
        brew.tangaria.settings.MAngband = {
          nick = lib.mkDefault "PLAYER";
          pass = lib.mkDefault "pass";
          meta_address = lib.mkDefault "mangband.org";
          meta_port = lib.mkDefault 8802;
          DisableNumlock = lib.mkDefault true;
          LighterBlue = lib.mkDefault true;
          IntroMusic = lib.mkDefault false;
        };

        home.packages = [ client ];
        xdg.configFile."tangaria/pwmangclient.ini".source = configFile;
      };
    };
}

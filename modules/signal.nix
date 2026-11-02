{ ... }:
{
  flake.modules.homeManager.signal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.signal;
      tomlFormat = pkgs.formats.toml { };
      historyDir = "${config.xdg.dataHome}/signal-mcp";
      # A fixed path the config can name: MCP clients start the servers with
      # too little environment to find the runtime directory.
      socketPath = "${config.xdg.stateHome}/signal-cli/socket";
      configPath = "${config.xdg.configHome}/signal-mcp/config.toml";
      signalMcp = mode: {
        command = lib.getExe pkgs.signal-mcp;
        args = [
          mode
          configPath
        ];
      };
      tool = server: name: "mcp__plugin_hm_${server}__${name}";
    in
    {
      options.brew.signal = {
        enable = lib.mkEnableOption ''
          signal-cli as a linked Signal device, a recorded message history, and
          MCP servers to read it and to send
        '';
      };
      config = lib.mkIf cfg.enable {
        # Linking (signal-cli link) and account maintenance run by hand.
        home.packages = [ pkgs.signal-cli ];

        # The socket is the daemon's only access control: only the user may
        # connect to it.
        systemd.user.sockets.signal-cli = {
          Unit.Description = "signal-cli JSON-RPC socket";
          Socket = {
            ListenStream = socketPath;
            DirectoryMode = "0700";
            SocketMode = "0600";
          };
          Install.WantedBy = [ "sockets.target" ];
        };
        systemd.user.services.signal-cli = {
          Unit = {
            Description = "signal-cli daemon holding the linked Signal account";
            Requires = [ "signal-cli.socket" ];
            After = [ "signal-cli.socket" ];
          };
          Service = {
            # Manual receive mode leaves messages queued on Signal's servers
            # until the ingester subscribes, so none arrive with no one
            # listening.
            ExecStart = lib.escapeShellArgs [
              (lib.getExe pkgs.signal-cli)
              "daemon"
              "--receive-mode=manual"
              "--no-receive-stdout"
            ];
            # signal-cli takes the listening socket from standard input.
            # Output must then be named, or it would default to that socket.
            StandardInput = "socket";
            StandardOutput = "journal";
            StandardError = "journal";
            UMask = "0077";
            Restart = "on-failure";
          };
        };

        systemd.user.tmpfiles.rules = [ "d ${historyDir} 0700 - - -" ];
        xdg.configFile."signal-mcp/config.toml".source = tomlFormat.generate "signal-mcp-config.toml" {
          signal = {
            database = "${historyDir}/messages.db";
            socket = socketPath;
          };
        };

        systemd.user.services.signal-mcp-ingest = {
          Unit = {
            Description = "Records received Signal messages for signal-mcp";
            Requires = [ "signal-cli.socket" ];
            After = [ "signal-cli.socket" ];
          };
          Service = {
            ExecStart = lib.escapeShellArgs [
              (lib.getExe pkgs.signal-mcp)
              "ingest"
              configPath
            ];
            UMask = "0077";
            # The subscription, and with it this process, ends whenever the
            # daemon restarts.
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = [ "default.target" ];
        };

        programs.mcp.servers = {
          signal = signalMcp "read";
          signal-send = signalMcp "send";
        };
        # Messages are written by other people and read in the same session
        # as everything else, so nothing goes out without the owner seeing it.
        programs.claude-code.settings.permissions = {
          allow = map (tool "signal") [
            "signal_list_conversations"
            "signal_read_conversation"
            "signal_search"
            "signal_find"
          ];
          ask = [ (tool "signal-send" "signal_send") ];
        };
      };
    };
}

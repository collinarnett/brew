{ ... }:
{
  flake.modules.homeManager.proton-calendar =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.proton-calendar;
      tool = name: "mcp__plugin_hm_proton-calendar__${name}";
    in
    {
      options.brew.proton-calendar = {
        enable = lib.mkEnableOption "Proton Calendar access through proton-cal's MCP server";
      };
      config = lib.mkIf cfg.enable {
        # proton-cal login stores its session under ~/.config/proton-cal, so
        # the CLI is installed alongside the server.
        home.packages = [ pkgs.proton-cal ];
        programs.mcp.servers.proton-calendar = {
          command = lib.getExe pkgs.proton-cal;
          args = [ "mcp" ];
        };
        # Mail is untrusted input read in the same session, so a message must
        # not be able to change the calendar without the owner seeing it.
        programs.claude-code.settings.permissions = {
          allow = map tool [
            "list_calendars"
            "get_calendar"
            "list_events"
            "get_event"
          ];
          ask = map tool [
            "create_calendar"
            "create_event"
            "update_event"
            "delete_event"
            "update_calendar"
          ];
          deny = [ (tool "delete_calendar") ];
        };
      };
    };
}

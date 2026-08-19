{ ... }:
{
  flake.modules.homeManager.ghostty =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.ghostty;
      # Tab bar dimensions follow the terminal font size so the bar scales
      # with it; the ratios reproduce the original 12pt look (24/20/12/6px).
      headerbarHeight = 2 * cfg.fontSize;
      tabHeight = 5 * cfg.fontSize / 3;
      tabPadding = cfg.fontSize / 2;
      tabBarCss = pkgs.writeText "ghostty-tabs.css" ''
        headerbar {
          min-height: ${toString headerbarHeight}px;
          padding: 0;
          margin: 0;
        }

        /* A translucent tab bar needs every GTK layer behind it to paint
           nothing: with background-opacity < 1 ghostty removes the window's
           `background` class, but libadwaita still paints the bare window
           node, the toolbar-view chrome, and AdwTabBar's internal
           revealer/box with opaque theme colors (verified per-node with
           color probes in a headless sway). Clear them all, then paint the
           bar veil on the tabbar node alone at the same alpha as
           background-opacity so the bar matches the terminal. */
        window.window,
        taboverview,
        toolbarview,
        .bottom-bar,
        windowhandle,
        tabbar revealer,
        tabbar .box,
        tabbar scrolledwindow,
        tabbar tabbox {
          background: none;
          box-shadow: none;
        }

        tabbar {
          background: rgba(40, 42, 54, 0.8);
        }

        tabbar tabbox {
          margin: 0;
          padding: ${toString tabPadding}px 0;
          min-height: 10px;
        }

        /* Fade-style tabs in the Dracula tab palette (inactive #6272a4,
           active #f8f8f2 italic, text #282a36). The background is a
           horizontal gradient fading to transparent at both edges; the
           faded zone reveals the translucent bar behind. */
        tabbar tabbox tab {
          margin: 0 3px;
          min-height: ${toString tabHeight}px;
          padding: 0 ${toString (2 * cfg.fontSize)}px;
          border-radius: 0;
          box-shadow: none;
          background-color: transparent;
          background-image: linear-gradient(
            to right,
            rgba(98, 114, 164, 0),
            rgb(98, 114, 164) 30%,
            rgb(98, 114, 164) 70%,
            rgba(98, 114, 164, 0)
          );
          color: #282a36;
          font-family: "Fira Code";
          font-size: ${toString cfg.fontSize}px;
        }

        tabbar tabbox tab:selected {
          background-image: linear-gradient(
            to right,
            rgba(248, 248, 242, 0),
            rgb(248, 248, 242) 30%,
            rgb(248, 248, 242) 70%,
            rgba(248, 248, 242, 0)
          );
          color: #282a36;
          font-style: italic;
        }

        /* GTK CSS cannot remove the tab close button widget, so collapse it
           to nothing. */
        tabbar tabbox tab button {
          opacity: 0;
          min-width: 0;
          min-height: 0;
          margin: 0;
          padding: 0;
        }
      '';
    in
    {
      options.brew.ghostty = {
        enable = lib.mkEnableOption "ghostty";
        fontSize = lib.mkOption {
          type = lib.types.int;
          default = 12;
          description = "Terminal font size in points.";
        };
      };
      config = lib.mkIf cfg.enable {
        programs.ghostty = {
          enable = true;
          settings = {
            theme = "Dracula";
            font-family = "Fira Code";
            font-size = cfg.fontSize;
            background-opacity = 0.8;
            confirm-close-surface = false;
            # Tab bar: bottom, compact tabs, thinned via CSS.
            gtk-tabs-location = "bottom";
            gtk-wide-tabs = false;
            # With background-opacity < 1, window-theme = ghostty makes
            # ghostty paint the chrome with the terminal's alpha instead of
            # libadwaita painting opaque @window_bg_color under the tab bar
            # (ghostty discussion #3190); without it the bar cannot be
            # translucent no matter what the CSS says.
            window-theme = "ghostty";
            gtk-custom-css = toString tabBarCss;
          };
        };
      };
    };
}

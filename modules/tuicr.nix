{ ... }:
{
  flake.modules.homeManager.tuicr =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        mkEnableOption
        mkOption
        mkIf
        types
        filterAttrs
        optionalAttrs
        ;
      cfg = config.brew.tuicr;
      tomlFormat = pkgs.formats.toml { };

      # config.toml is assembled from the typed options below. Every key maps
      # to a nullable option; only explicitly-set keys are written, so tuicr
      # keeps ownership of its own defaults for anything left unset.
      scalars = filterAttrs (_: v: v != null) {
        theme = cfg.theme;
        appearance = cfg.appearance;
        theme_dark = cfg.themeDark;
        theme_light = cfg.themeLight;
        diff_view = cfg.diffView;
        ignore_whitespace = cfg.ignoreWhitespace;
        show_file_list = cfg.showFileList;
        mouse = cfg.mouse;
        leader = cfg.leader;
        comment_vim = cfg.commentVim;
        comment_tab_width = cfg.commentTabWidth;
        wrap = cfg.wrap;
        cursor_line = cfg.cursorLine;
        transparent_background = cfg.transparentBackground;
        scroll_offset = cfg.scrollOffset;
        no_update_check = cfg.noUpdateCheck;
        review_watch_interval_ms = cfg.reviewWatchIntervalMs;
        backend = cfg.backend;
      };

      configToml =
        scalars
        // optionalAttrs (cfg.commentTypes != [ ]) {
          comment_types = map (ct: filterAttrs (_: v: v != null) ct) cfg.commentTypes;
        }
        // optionalAttrs (cfg.forge.commentTypePrefix != null) {
          forge.comment_type_prefix = cfg.forge.commentTypePrefix;
        };

      # Dracula is not one of tuicr's bundled themes, so the module ships it as
      # a local theme (palette + matching syntax .tmTheme) that tuicr resolves
      # by name from the themes/ directory. Palette: https://spec.draculatheme.com/
      draculaTheme = {
        panel_bg = "#282a36"; # Background
        bg_highlight = "#44475a"; # Current Line / Selection
        fg_primary = "#f8f8f2"; # Foreground
        fg_secondary = "#6272a4"; # Comment
        fg_dim = "#44475a"; # Current Line grey, used for dimmest text

        diff_add = "#50fa7b"; # Green
        diff_add_bg = "#233b2c"; # Background tinted toward green
        diff_del = "#ff5555"; # Red
        diff_del_bg = "#3d2531"; # Background tinted toward red
        diff_context = "#f8f8f2";
        diff_hunk_header = "#8be9fd"; # Cyan
        expanded_context_fg = "#6272a4";

        syntax_add_bg = "#233b2c";
        syntax_del_bg = "#3d2531";
        syntax_theme = "dracula.tmTheme"; # Resolved relative to this file.

        file_added = "#50fa7b"; # Green
        file_modified = "#ffb86c"; # Orange
        file_deleted = "#ff5555"; # Red
        file_renamed = "#bd93f9"; # Purple

        reviewed = "#50fa7b"; # Green
        pending = "#ffb86c"; # Orange

        comment_note = "#8be9fd"; # Cyan
        comment_suggestion = "#bd93f9"; # Purple
        comment_issue = "#ff5555"; # Red
        comment_praise = "#50fa7b"; # Green

        border_focused = "#bd93f9"; # Purple
        border_unfocused = "#44475a";
        status_bar_bg = "#44475a";
        cursor_color = "#ffb86c"; # Orange
        cursor_line_bg = "#44475a"; # Current Line
        branch_name = "#bd93f9"; # Purple
        help_indicator = "#6272a4"; # Comment

        message_info_fg = "#282a36";
        message_info_bg = "#8be9fd"; # Cyan
        message_warning_fg = "#282a36";
        message_warning_bg = "#ffb86c"; # Orange
        message_error_fg = "#282a36";
        message_error_bg = "#ff5555"; # Red
        update_badge_fg = "#282a36";
        update_badge_bg = "#f1fa8c"; # Yellow

        mode_fg = "#282a36";
        mode_bg = "#bd93f9"; # Purple
      };

      # Helper for the many nullable config.toml keys.
      nullOpt =
        type: description:
        mkOption {
          type = types.nullOr type;
          default = null;
          inherit description;
        };
    in
    {
      options.brew.tuicr = {
        enable = mkEnableOption "tuicr, a code-review TUI";

        theme = mkOption {
          type = types.str;
          default = "dracula";
          description = ''
            Theme name. A bundled tuicr theme (e.g. "gruvbox-dark", "nord-dark")
            or a local theme in the themes/ directory. The module ships a
            "dracula" local theme, which is the default.
          '';
        };

        appearance = nullOpt (types.enum [
          "dark"
          "light"
          "system"
        ]) "Appearance used when no explicit theme is set.";
        themeDark = nullOpt types.str "Theme for dark appearance (paired with themeLight).";
        themeLight = nullOpt types.str "Theme for light appearance (paired with themeDark).";
        diffView = nullOpt (types.enum [
          "unified"
          "side-by-side"
        ]) "Diff layout.";
        ignoreWhitespace = nullOpt types.bool "Ignore all whitespace in local VCS diffs.";
        showFileList = nullOpt types.bool "Show the file list panel on startup.";
        mouse = nullOpt types.bool "Wheel scrolling, clicks, and drag-to-select.";
        leader = nullOpt types.str "Single-character leader prefix.";
        commentVim = nullOpt types.bool "Vim modal editing in the comment box.";
        commentTabWidth = nullOpt types.int "Spaces inserted by Tab in the vim comment box.";
        wrap = nullOpt types.bool "Line wrap in the diff view.";
        cursorLine = nullOpt types.bool "Highlight the current cursor line.";
        transparentBackground = nullOpt types.bool "Let the terminal background show through panels.";
        scrollOffset = nullOpt types.int "Minimum lines kept above/below the cursor.";
        noUpdateCheck = nullOpt types.bool "Skip the startup update check.";
        reviewWatchIntervalMs = nullOpt types.int "Poll interval for persisted review sessions (0 disables).";
        backend = nullOpt (types.enum [
          "libgit2"
          "cli"
        ]) "Git backend.";

        commentTypes = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                id = mkOption {
                  type = types.str;
                  description = "Stable internal id, saved in sessions.";
                };
                label = nullOpt types.str "Visible tag in UI and export. Defaults to id uppercased.";
                definition = nullOpt types.str "Guidance text included in the exported legend.";
                color = nullOpt types.str "Badge/border color: terminal name or #RRGGBB.";
              };
            }
          );
          default = [ ];
          description = "Comment categories. Empty uses tuicr's built-in set.";
        };

        forge.commentTypePrefix = nullOpt types.bool "Prepend [TYPE] to comment bodies on submit.";
      };

      config = mkIf cfg.enable {
        home.packages = [ pkgs.tuicr ];

        xdg.configFile = {
          "tuicr/config.toml".source = tomlFormat.generate "tuicr-config.toml" configToml;
          "tuicr/themes/dracula.toml".source = tomlFormat.generate "tuicr-dracula.toml" draculaTheme;
          "tuicr/themes/dracula.tmTheme".source = ../configurations/tuicr/dracula.tmTheme;
        };
      };
    };
}

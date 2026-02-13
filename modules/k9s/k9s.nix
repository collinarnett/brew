{ config, lib, ... }:
let
  cfg = config.brew.k9s;
  user = config.brew.user;
in
{
  options.brew.k9s.enable = lib.mkEnableOption "k9s";
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.k9s = {
        enable = true;
        settings = {
          skin = "dracula";
        };
        skins.dracula.k9s =
          let
            fgColor = "#f8f8f2";
            bgColor = "#282a36";
            selection = "#44475a";
            comment = "#6272a4";
            cyan = "#8be9fd";
            green = "#50fa7b";
            orange = "#ffb86c";
            purple = "#bd93f9";
            pink = "#ff79c6";
            red = "#ff5555";
            yellow = "#f1fa8c";
          in
          {
            body.fgColor = fgColor;
            body.bgColor = bgColor;
            body.logoColor = purple;
            dialog = {
              inherit fgColor bgColor;
              buttonFgColor = fgColor;
              buttonBgColor = purple;
              buttonFocusFgColor = yellow;
              buttonFocusBgColor = pink;
              labelFgColor = orange;
              fieldFgColor = fgColor;
            };
            frame = {
              border.fgColor = selection;
              border.focusColor = selection;
              menu.fgColor = fgColor;
              menu.keyColor = pink;
              menu.numKeyColor = pink;
              crumbs.fgColor = fgColor;
              crumbs.bgColor = selection;
              crumbs.activeColor = selection;
              status = {
                newColor = cyan;
                modifyColor = purple;
                addColor = green;
                errorColor = red;
                highlightColor = orange;
                killColor = comment;
                completedColor = comment;
              };
              title = {
                inherit fgColor;
                bgColor = selection;
                highlightColor = orange;
                counterColor = purple;
                filterColor = pink;
              };
            };
            info.fgColor = pink;
            info.sectionColor = fgColor;
            prompt.fgColor = fgColor;
            prompt.bgColor = bgColor;
            prompt.suggestColor = purple;
            views = {
              charts.bgColor = "default";
              charts.defaultDialColors = [
                purple
                red
              ];
              charts.defaultChartColors = [
                purple
                red
              ];
              logs = {
                inherit fgColor bgColor;
                indicator = {
                  inherit fgColor;
                  bgColor = purple;
                  toggleOnColor = green;
                  toggleOffColor = cyan;
                };
              };
              table = {
                inherit fgColor bgColor;
                header = {
                  inherit fgColor bgColor;
                  sorterColor = cyan;
                };
              };
              xray = {
                inherit fgColor bgColor;
                cursorColor = selection;
                graphicColor = purple;
                showIcons = false;
              };
              yaml.keyColor = pink;
              yaml.colonColor = purple;
              yaml.valueColor = fgColor;
            };
          };
      };
    };
  };
}

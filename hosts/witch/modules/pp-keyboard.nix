{pkgs, ...}: rec {
  # ppkb-layout = pkgs.fetchurl {
  #          url = "https://codeberg.org/phalio/ppkb-layouts/src/commit/881c44112f7832ab778a6966a625a1dbb0c9ca7e/xkb/pp";
  #          sha256 = "sha256-q2F/2L2YKJvM3X4fSAIZgheT0KgxFQnCkYschLZrEuQ=";
  #        };

  services.xserver = {
    enable = true;
    layout = "pine";
    extraLayouts = {
      pine = {
        description = "Pinephone keyboard layout";
        languages = ["eng"];
        symbolsFile = ./pp;
      };
    };
  };
}

{ ... }:
{
  flake.modules.homeManager.anki =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.anki;
      # Anki renders [latex] note fields by shelling out to latex and
      # dvipng/dvisvgm at runtime. The source-built anki inherits PATH (the
      # anki-bin package runs inside a buildFHSEnv sandbox and does not), so it
      # is wrapped with a minimal TeX toolchain scoped to Anki alone. Nothing is
      # added to the global user profile. The TeX package set matches Anki's
      # default preamble, which loads amssymb and amsmath.
      tex = pkgs.texliveBasic.withPackages (
        ps: with ps; [
          dvipng
          dvisvgm
          amsmath
          amsfonts
        ]
      );
      anki-with-latex = pkgs.symlinkJoin {
        name = "anki-with-latex";
        paths = [ pkgs.anki ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/anki \
            --prefix PATH : ${lib.makeBinPath [ tex ]}
        '';
      };
    in
    {
      options.brew.anki.enable = lib.mkEnableOption "anki";
      config = lib.mkIf cfg.enable {
        home.packages = [ anki-with-latex ];
      };
    };
}

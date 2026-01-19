final: prev: {
  leiningen = prev.leiningen.override {
    jdk = final.openjdk21.overrideAttrs (prev_: {
      src = final.fetchFromGitHub {
        owner = "openjdk";
        repo = "wakefield";
        rev = "bbb963506776619e2d34740148e6ea67fba5eb2d";
        hash = "sha256-ERuuBzB9vhnV7oGhc3fK1vpnQvQVDIpo++w0DXXMVGM=";
      };
      patches = prev_.patches ++ [ ./patches/jdk-xdg-open-support.patch ];
      nativeBuildInputs = prev_.nativeBuildInputs ++ [
        final.shaderc
        final.wayland
      ];
      configureFlags = prev_.configureFlags ++ [
        "--with-libffi-include=${final.libffi.dev}/include"
        "--with-libffi-lib=${final.libffi.out}/lib"
        "--with-wayland-include=${final.wayland.dev}/include"
        "--with-wayland-lib=${final.wayland.out}/lib"
        "--with-vulkan-include=${final.vulkan-headers}/include"
        "--with-vulkan-shader-compiler=glslc"
      ];
    });
  };
  emacs = prev.emacsWithPackagesFromUsePackage {
    config = ../configurations/emacs/emacs.el;
    alwaysEnsure = true;
    defaultInitFile = true;
    package = prev.emacs-unstable-pgtk;
    extraEmacsPackages =
      epkgs: with epkgs; [
        use-package
        treesit-grammars.with-all-grammars
        (epkgs.trivialBuild {
          pname = "org-fc";
          version = "20201121";
          src = prev.fetchFromGitHub {
            owner = "l3kn";
            repo = "org-fc";
            rev = "cc191458a991138bdba53328690a569b8b563502";
            sha256 = "sha256-wzMSgS4iZfpKOICqQQuQYNPb2h7i4tTWsMs7mVmgBt8=";
          };
          packageRequires = [
            epkgs.elpaPackages.org
            epkgs.melpaPackages.hydra
          ];
          propagatedUserEnvPkgs = with prev; [
            findutils
            gawk
          ];

          postInstall = ''
            cp -r ./awk/ $LISPDIR/
          '';

          meta = {
            description = "Spaced Repetition System for Emacs org-mode";
            license = prev.lib.licenses.gpl3;
          };
        })
      ];
  };
}

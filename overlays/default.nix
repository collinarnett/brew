final: prev: {
  openjdk25-wakefield = prev.openjdk25.overrideAttrs (old: {
    pname = "openjdk-wakefield";
    version = "25.0.2";

    src = final.fetchFromGitHub {
      owner = "openjdk";
      repo = "wakefield";
      rev = "0bf2bd412d3323fa534be586b6f449fb77ea2e4c";
      hash = "sha256-vQlCarQVdyj6NRcIiYT1uMkYFLp6YjLPMwsOP+VC7ns=";
    };

    patches = old.patches ++ [ ./patches/jdk-xdg-open-support.patch ];

    nativeBuildInputs = old.nativeBuildInputs ++ [
      final.wayland-scanner
    ];

    buildInputs = (old.buildInputs or []) ++ [
      final.wayland
      final.libxkbcommon
      final.wayland-protocols
    ];

    configureFlags = old.configureFlags ++ [
      "--with-wayland-include=${final.wayland.dev}/include"
      "--with-wayland-lib=${final.wayland.out}/lib"
      "--with-wayland-protocols=${final.wayland-protocols}/share/wayland-protocols"
      "--with-xkbcommon-include=${final.libxkbcommon.dev}/include"
      "--with-xkbcommon-lib=${final.libxkbcommon.out}/lib"
    ];
  });

  leiningen = prev.leiningen.override {
    jdk = final.openjdk25-wakefield;
  };
  emacs = prev.emacsWithPackagesFromUsePackage {
    config = ../configurations/emacs/emacs.el;
    alwaysEnsure = true;
    defaultInitFile = true;
    package = prev.emacs-unstable-pgtk;
    override = epkgs: epkgs // {
      claude-code = epkgs.melpaPackages.claude-code.overrideAttrs (old: {
        src = prev.fetchFromGitHub {
          owner = "stevemolitor";
          repo = "claude-code.el";
          rev = "main";
          sha256 = "sha256-ISlD6q1hceckry1Jd19BX1MfobHJxng5ulX2gq9f644=";
        };
        packageRequires = with epkgs; [
          eat
          melpaPackages.inheritenv
          melpaPackages.markdown-mode
          melpaPackages.projectile
          melpaPackages.transient
        ];
      });
    };
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
        (epkgs.trivialBuild {
          pname = "monet";
          version = "0-unstable-2025-09-25";
          src = prev.fetchFromGitHub {
            owner = "stevemolitor";
            repo = "monet";
            rev = "72a18d372fef4b0971267bf13f127dcce681859a";
            sha256 = "sha256-3e5DIR+X6JLDaY7vRDutH3EAsyaqK3Jc73ugZTDRUrQ=";
          };
          packageRequires = [
            epkgs.elpaPackages.websocket
          ];

          meta = {
            description = "Implements Claude Code IDE protocol for Emacs";
            license = prev.lib.licenses.mit;
          };
        })
      ];
  };
}

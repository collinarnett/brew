final: prev: {
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
  python312 = prev.python312.override {
    packageOverrides = finalPkgs: prevPkgs: {
      # Remove after April 30, 2025 and update nixos-unstable pin when https://nixpk.gs/pr-tracker.html?pr=400080 propagates
      flask-limiter = prevPkgs.flask-limiter.overrideAttrs {
        patches = [
          # permit use of rich < 15 -- remove when updating past 3.12
          (final.fetchpatch {
            url = "https://github.com/alisaifee/flask-limiter/commit/008a5c89f249e18e5375f16d79efc3ac518e9bcc.patch";
            hash = "sha256-dvTPVnuPs7xCRfUBBA1bgeWGuevFUZ+Kgl9MBHdgfKU=";
          })
        ];
      };
    };
  };
  python312Packages = final.python312.pkgs;
}

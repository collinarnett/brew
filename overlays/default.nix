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
}

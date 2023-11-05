{pkgs, ...}:
pkgs.emacsWithPackagesFromUsePackage {
  config = ./emacs.el;
  alwaysEnsure = true;
  defaultInitFile = true;
  package = pkgs.emacs-unstable;
  extraEmacsPackages = epkgs:
    with epkgs; [
      use-package
    ];
}

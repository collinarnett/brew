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
  override = final: prev: {
    smartparens = prev.melpaPackages.smartparens.overrideAttrs (old: {
      src = pkgs.fetchFromGitHub {
        owner = "Fuco1";
        repo = "smartparens";
        rev = "a5c68cac1bea737b482a37aa92de4f6efbf7580b";
        sha256 = "sha256-ldt0O9nQP3RSsEvF5+irx6SRt2GVWbIao4IOO7lOexM=";
      };
    });
  };
}

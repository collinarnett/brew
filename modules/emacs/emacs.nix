{pkgs, ...}: {
  environment.systemPackages = [
    (pkgs.emacsWithPackagesFromUsePackage {
      config = ./emacs.el;
      alwaysEnsure = true;
      defaultInitFile = true;
      package = pkgs.emacsUnstable;
      extraEmacsPackages = epkgs:
        with epkgs; [
          use-package
        ];
    })
  ];
}

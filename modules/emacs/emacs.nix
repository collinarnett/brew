{pkgs, ...}: {
  environment.systemPackages = [
    (pkgs.emacsWithPackagesFromUsePackage {
      config = ./emacs.el;
      defaultInitFile = true;
      package = pkgs.emacsUnstable;
    })
  ];
}

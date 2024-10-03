final: prev: {
  emacs = prev.emacsWithPackagesFromUsePackage {
    config = ../configurations/emacs/emacs.el;
    alwaysEnsure = true;
    defaultInitFile = true;
    package = prev.emacs-unstable;
    extraEmacsPackages = epkgs:
      with epkgs; [
        use-package
      ];
    override = self: super: {
      smartparens = super.melpaPackages.smartparens.overrideAttrs (old: {
        src = prev.fetchFromGitHub {
          owner = "Fuco1";
          repo = "smartparens";
          rev = "a5c68cac1bea737b482a37aa92de4f6efbf7580b";
          sha256 = "sha256-ldt0O9nQP3RSsEvF5+irx6SRt2GVWbIao4IOO7lOexM=";
        };
      });
    };
  };
  python312 = prev.python312.override {
    packageOverrides = finalPkgs: prevPkgs: {
      nose = prevPkgs.nose.overrideAttrs {
        patches = [
          (final.fetchpatch2 {
            url = "https://github.com/NixOS/nixpkgs/raw/599e471d78801f95ccd2c424a37e76ce177e50b9/pkgs/development/python-modules/nose/0001-nose-python-3.12-fixes.patch";
            hash = "sha256-aePOvO5+TJL4JzXywc7rEiYRzfdObSI9fg9Cfrp+e2o=";
          })
        ];
      };
    };
  };
  python312Packages = final.python312.pkgs;
}

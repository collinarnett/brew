final: prev: {
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

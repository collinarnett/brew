# shell.nix
with import <nixpkgs> {}; let
  sops-nix = builtins.fetchTarball {
    url = "https://github.com/Mic92/sops-nix/archive/master.tar.gz";
  };
in
  mkShell {
    sopsPGPKeys = ["./secrets/keys/collin.asc"];

    nativeBuildInputs = [(pkgs.callPackage sops-nix {}).sops-import-keys-hook];
  }

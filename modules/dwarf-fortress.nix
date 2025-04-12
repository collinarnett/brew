{ pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = [
    (pkgs.dwarf-fortress-packages.dwarf-fortress-full.override {
      enableTWBT = false;
      enableTextMode = true;
    })
  ];
}

{ lib, pkgs, ... }:
let
  k3s = pkgs.k3s.overrideAttrs
    (old: rec { buildInputs = old.buildInputs ++ [ pkgs.ipset ]; });
in {
  networking.firewall.allowedTCPPorts = [ 6443 80 443 10250 ];
  networking.firewall.allowedUDPPorts = [ 8472 ];
  services.k3s = {
    enable = true;
    role = "server";
    package = k3s;
  };
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "k3s-reset-node"
      (builtins.readFile ./k3s-reset-node))
  ];
}

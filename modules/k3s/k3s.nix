{ lib, pkgs, ... }: {
  networking.firewall.allowedTCPPorts = [ 6443 ];
  networking.firewall.allowedUDPPorts = [ 8472 ];
  services.k3s = {
    enable = true;
    role = "server";
  };
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "k3s-reset-node"
      (builtins.readFile ./k3s-reset-node))
  ];
}

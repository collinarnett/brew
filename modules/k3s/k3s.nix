{ lib, pkgs, ... }: {
  networking.firewall.allowedTCPPorts = [ 6443 ];
  services.k3s = {
    enable = true;
    role = "server";
  };
  networking.firewall.enable = false;
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "k3s-reset-node"
      (builtins.readFile ./k3s-reset-node))
  ];
}

{ lib, pkgs, ... }: {
  networking.firewall.allowedTCPPorts = [ 6443 80 443 10250 ];
  networking.firewall.allowedUDPPorts = [ 8472 ];
  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = "--write-kubeconfig-mode 644";
  };
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "k3s-reset-node"
      (builtins.readFile ./k3s-reset-node))
  ];
}


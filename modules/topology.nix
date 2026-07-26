{ inputs, ... }:
{
  imports = [ inputs.nix-topology.flakeModule ];

  flake.modules.nixos.topology = {
    imports = [ inputs.nix-topology.nixosModules.default ];
    # Every machine meshes over Yggdrasil via the clan yggdrasil service. The
    # ygg0 tun is created at runtime, so nix-topology cannot detect it the way
    # it detects systemd-networkd interfaces; declare it for the diagram.
    topology.self.interfaces.ygg.network = "yggdrasil";
  };

  perSystem.topology.modules = [
    (
      { config, ... }:
      let
        inherit (config.lib.topology) mkInternet mkRouter mkConnection;
      in
      {
        networks = {
          yggdrasil = {
            name = "Yggdrasil";
            cidrv6 = "0200::/7";
            # Dashed to signal an overlay mesh rather than a physical segment.
            style = {
              primaryColor = "#70a5eb";
              secondaryColor = null;
              pattern = "dashed";
            };
          };
          home = {
            name = "Home";
            cidrv4 = "192.168.1.0/24";
          };
        };

        nodes.internet = mkInternet {
          connections = mkConnection "router" "wan";
        };

        nodes.router = mkRouter "Home Router" {
          info = "192.168.1.1";
          interfaces.wan = { };
          interfaces.lan = {
            addresses = [ "192.168.1.1" ];
            network = "home";
          };
          # azathoth is wired via eno2; ghoul associates over wifi (wlp195s0).
          connections.lan = [
            (mkConnection "azathoth" "eno2")
            (mkConnection "ghoul" "wlp195s0")
          ];
        };

        # Addresses below are live-verified (DHCP leases + yggdrasilctl getSelf),
        # since NetworkManager records none of this in the NixOS config.
        nodes.azathoth.interfaces = {
          eno2.addresses = [ "192.168.1.163" ];
          ygg.addresses = [ "200:230d:2965:e6b7:7c8f:84d2:efa9:96bc" ];
          # Host side of the libvirt NAT bridge; vampire is a guest reached
          # directly over it, so draw a point-to-point link rather than a
          # shared-network cloud (fewer crossing edges in the diagram).
          virbr0 = {
            addresses = [ "192.168.122.1" ];
            physicalConnections = [ (mkConnection "vampire" "enp2s0") ];
          };
        };

        nodes.ghoul.interfaces = {
          wlp195s0.addresses = [ "192.168.1.214" ];
          ygg.addresses = [ "200:95ee:404a:85f8:afda:866:bcde:80b" ];
        };

        # vampire is a libvirt guest on azathoth, reached over virbr0 — not a
        # standalone machine on the home LAN. parent/guestType render it nested
        # inside azathoth's card (the same modelling the microvm and
        # nixos-container extractors use for guests). It has no facter, so its
        # NIC is declared here rather than auto-detected.
        nodes.vampire = {
          parent = "azathoth";
          guestType = "libvirt";
          interfaces = {
            enp2s0.addresses = [ "192.168.122.132" ];
            ygg.addresses = [ "201:efeb:9971:20e:92b2:ae51:8ed6:88a1" ];
          };
        };
      }
    )
  ];
}

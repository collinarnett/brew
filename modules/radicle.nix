{ ... }:
{
  flake.modules.homeManager.radicle =
    {
      config,
      osConfig,
      lib,
      ...
    }:
    let
      cfg = config.brew.radicle;
      # The azathoth seed's node ID, derived from
      # vars/per-machine/azathoth/radicle/radicle_key.pub.
      seedNid = "z6MkgH2Be7jdCoDa177oMpLFatqHyLQmc8Hy2zcH1wkNYASd";
    in
    {
      options.brew.radicle.enable = lib.mkEnableOption "radicle";
      config = lib.mkIf cfg.enable {
        programs.radicle = {
          enable = true;
          uri.rad.browser.preferredNode = "garden.trexd.dev";
          settings = {
            publicExplorer = "https://garden.trexd.dev/nodes/$host/$rid$path";
            preferredSeeds = [ "${seedNid}@azathoth.clan:8776" ];
            # Each device carries its own Radicle identity (upstream forbids
            # sharing keys between devices), so name nodes after the host.
            node.alias = osConfig.networking.hostName;
          };
        };

        # The node only binds its control socket (node.listen is empty), so it
        # coexists with the system seed on azathoth. ConditionPathExists on the
        # keypair keeps it inactive until `rad auth` has created an identity.
        services.radicle.node = {
          enable = true;
          lazy.enable = true;
        };
      };
    };
}

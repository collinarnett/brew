# configuration in this file only applies to exampleHost host
#
# only my-config.* and zfs-root.* options can be defined in this file.
#
# all others goes to `configuration.nix` under the same directory as
# this file.
{
  system,
  pkgs,
  ...
}: {
  inherit pkgs system;
}

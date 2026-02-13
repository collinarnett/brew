{ lib, ... }:
{
  options.brew.user = lib.mkOption {
    type = lib.types.str;
    default = "collin";
    description = "Primary user for home-manager configuration";
  };
}

# Bypass Paywalls Clean — Firefox extension self-distributed (Mozilla-signed)
# via gitflic after its AMO takedown. The XPI store path is referenced directly
# by the firefox ExtensionSettings policy (force_installed file:// install_url).
# Update: bump version + url, then `nix store prefetch-file --name <file> <url>`.
{ fetchurl }:
let
  version = "4.3.8.1";
in
fetchurl {
  name = "bypass-paywalls-clean-${version}.xpi";
  url = "https://gitflic.ru/project/magnolia1234/bpc_uploads/blob/raw?file=bypass_paywalls_clean-${version}.xpi";
  hash = "sha256-pD+R7d3MjfuPojJkl4pGkXXkGa7JvKR6Fp26HFgM1QY=";
}

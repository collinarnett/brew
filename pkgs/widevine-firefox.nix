# Firefox discovers Gecko Media Plugins through MOZ_GMP_PATH, which must point
# at a directory holding the plugin library beside its manifest. nixpkgs ships
# the CDM in Chrome's layout, so relink it into the shape Firefox reads.
#
# The directory is named "system-installed" to match the value Firefox is given
# for media.gmp-widevinecdm.version. That pref normally holds a real version
# number and resolves against the profile; the sentinel is how the plugin is
# declared to live outside the profile instead.
{
  lib,
  runCommand,
  stdenv,
  widevine-cdm,
}:
let
  platformDir =
    if stdenv.hostPlatform.isx86_64 then
      "linux_x64"
    else if stdenv.hostPlatform.isAarch64 then
      "linux_arm64"
    else
      throw "widevine-firefox: no Widevine CDM for ${stdenv.hostPlatform.system}";
in
runCommand "widevine-firefox-${widevine-cdm.version}"
  {
    inherit (widevine-cdm) meta;
    passthru = { inherit (widevine-cdm) version; };
  }
  ''
    cdm=${lib.getOutput "out" widevine-cdm}/share/google/chrome/WidevineCdm
    install -d $out/gmp-widevinecdm/system-installed
    ln -s "$cdm/manifest.json" $out/gmp-widevinecdm/system-installed/manifest.json
    ln -s "$cdm/_platform_specific/${platformDir}/libwidevinecdm.so" \
      $out/gmp-widevinecdm/system-installed/libwidevinecdm.so
  ''

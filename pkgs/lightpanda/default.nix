{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:
let
  version = "0.2.7";
  platforms = {
    x86_64-linux = {
      binary = "lightpanda-x86_64-linux";
      hash = "sha256-cGrMzVDnChi4IG/Js8Fvy4V0uYS21prgWppCYv7KvxI=";
    };
    aarch64-linux = {
      binary = "lightpanda-aarch64-linux";
      hash = "sha256-C0LCBkVxnjzfYCKUrIH7zcEMi7NhBL4IbPMoTax4gAs=";
    };
  };
  platform =
    platforms.${stdenvNoCC.hostPlatform.system}
      or (throw "lightpanda: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "lightpanda";
  inherit version;

  src = fetchurl {
    url = "https://github.com/lightpanda-io/browser/releases/download/${version}/${platform.binary}";
    inherit (platform) hash;
  };

  dontUnpack = true;

  nativeBuildInputs = [ autoPatchelfHook ];

  installPhase = ''
    install -Dm755 $src $out/bin/lightpanda
  '';

  meta = {
    description = "Headless browser designed for AI and automation";
    homepage = "https://github.com/lightpanda-io/browser";
    license = lib.licenses.agpl3Only;
    mainProgram = "lightpanda";
    platforms = builtins.attrNames platforms;
  };
}

{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:
let
  version = "0.3.7";
  platforms = {
    x86_64-linux = {
      binary = "lightpanda-x86_64-linux";
      hash = "sha256-iVM5sCIFFxoYHd50OuAGi7RWSIQHb+rISCusqcISqlo=";
    };
    aarch64-linux = {
      binary = "lightpanda-aarch64-linux";
      hash = "sha256-TA7LKLT8+21bzoLshuFfxs3onOoWjPOEBJTw7iZ1WFI=";
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

{ stdenv, python3, clan-cli }:
stdenv.mkDerivation {
  pname = "clan-commands-json";
  version = clan-cli.version or "0.0.0";
  dontUnpack = true;
  nativeBuildInputs = [
    (python3.withPackages (ps: [ (ps.toPythonModule clan-cli) ]))
  ];
  buildPhase = ''
    python3 ${./clan-mcp/dump-commands.py} > commands.json
  '';
  installPhase = ''
    install -Dm644 commands.json $out/share/clan-mcp/commands.json
  '';
}

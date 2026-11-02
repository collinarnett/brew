{
  lib,
  fetchFromGitHub,
  buildNpmPackage,
}:

buildNpmPackage {
  pname = "monica-mcp";
  version = "2.1.1-unstable-2026-10-05";

  src = fetchFromGitHub {
    owner = "Jacob-Stokes";
    repo = "monica-mcp";
    rev = "eafc5358f6fb79e728cd9ff770ca047ce283a075";
    hash = "sha256-9FTPbpLYuHLTP+EAGzaeGzDBH2oPB0H1drWToXhYR6c=";
  };

  # Reads and changes become separate tools so changes can require approval,
  # a --config JSON file replaces the environment and needs an explicit
  # Monica URL, and uploads from local paths are off.
  patches = [ ./monica-mcp-brew.patch ];

  npmDepsHash = "sha256-/jtwSGKth31cpJvctkHSdh4vRDkFxxKkENxDyc5Tu1w=";

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    npm test
    runHook postCheck
  '';

  meta = {
    description = "MCP server for Monica 4, the personal CRM";
    homepage = "https://github.com/Jacob-Stokes/monica-mcp";
    license = lib.licenses.mit;
    mainProgram = "monica-mcp";
  };
}

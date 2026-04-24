{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage (finalAttrs: {
  pname = "mcp-conformance";
  version = "0.1.16";

  src = fetchFromGitHub {
    owner = "modelcontextprotocol";
    repo = "conformance";
    tag = "v${finalAttrs.version}";
    hash = "sha256-NbI2xVf4TLl3ChIRZfVY0E5km/a+o5/NkBp4FPZZKq0=";
  };

  npmDepsHash = "sha256-oe7bKHnAbnQZNPVklPOMvyepQkvAoMQz4vadW/slFtg=";

  meta = {
    description = "Conformance tests for Model Context Protocol servers and clients";
    homepage = "https://github.com/modelcontextprotocol/conformance";
    license = lib.licenses.mit;
    mainProgram = "conformance";
    maintainers = [ ];
  };
})

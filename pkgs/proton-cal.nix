{
  lib,
  fetchFromGitHub,
  buildGo127Module,
}:

buildGo127Module (finalAttrs: {
  pname = "proton-cal";
  version = "0.1.3";

  src = fetchFromGitHub {
    owner = "cheeseandcereal";
    repo = "proton-cal";
    tag = "v${finalAttrs.version}";
    hash = "sha256-uoHYvL0XnYd2lmmL4bxAbKsgUmAq5JecmK4VBKuaKJc=";
  };

  vendorHash = "sha256-HhxjlctVq+wmlWYMzYNiTvg5/fBoUe/6jTIwrpWgExs=";

  # go.mod names Go 1.27.3 and nixpkgs carries 1.27.1. A patch release adds no
  # language features, and the unit tests run against this toolchain.
  postPatch = ''
    substituteInPlace go.mod --replace-fail "go 1.27.3" "go 1.27.1"
  '';

  ldflags = [
    "-s"
    "-X github.com/cheeseandcereal/proton-cal/pkg/cli.version=${finalAttrs.version}"
  ];

  # These tests sign in to a real Proton account, behind an `integration` build
  # tag.
  excludedPackages = [ "pkg/integration" ];

  # Upstream stamps the version only into the release binary, and this test
  # asserts the unstamped "dev"; here the stamp also reaches the test build.
  checkFlags = [ "-skip=^TestCLIVersionFlag$" ];

  meta = {
    description = "CLI and MCP server for Proton Calendar with client-side end-to-end encryption";
    homepage = "https://github.com/cheeseandcereal/proton-cal";
    license = lib.licenses.unlicense;
    mainProgram = "proton-cal";
  };
})

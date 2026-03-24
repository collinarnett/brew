{
  lib,
  fetchFromGitHub,
  buildNpmPackage,
}:

buildNpmPackage {
  pname = "gitlab-mcp";
  version = "2.0.34";

  src = fetchFromGitHub {
    owner = "zereight";
    repo = "gitlab-mcp";
    rev = "989eeec3374a6ad6e4ec7f75b35bb29fe70ffec0";
    hash = "sha256-OpY2hqcIAr9F5CFtpBENWdJLFFkyef7KZsQXce7zDWc=";
  };

  npmDepsHash = "sha256-tJou/TMZZvlPiMJgEEpE7oj3+B1XMrcCdQBDcNHsNxE=";

  postInstall = ''
    ln -s "$out/bin/@zereight/mcp-gitlab" "$out/bin/mcp-gitlab"
  '';

  meta = {
    description = "MCP server for using the GitLab API";
    homepage = "https://github.com/zereight/gitlab-mcp";
    license = lib.licenses.mit;
    mainProgram = "mcp-gitlab";
  };
}

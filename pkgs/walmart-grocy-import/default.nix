{
  lib,
  python3,
  lightpanda,
}:
python3.pkgs.buildPythonApplication {
  pname = "walmart-grocy-import";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = with python3.pkgs; [
    setuptools
  ];

  dependencies = with python3.pkgs; [
    browser-cookie3
    playwright
    pydantic
    requests
    thefuzz
  ];

  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [ lightpanda ])
  ];

  meta = {
    description = "Import Walmart order history into Grocy inventory";
    license = lib.licenses.mit;
  };
}

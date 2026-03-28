# uv2nix Python Project

Initialize and package Python projects using uv2nix for reproducible Nix builds.

## What is uv2nix

uv2nix takes a [uv](https://docs.astral.sh/uv/) workspace and generates Nix derivations from `uv.lock` using pure Nix code. It replaces poetry2nix, pip2nix, and ad-hoc `python3.withPackages` wrappers with a single, principled workflow: uv manages the Python side, Nix builds it reproducibly.

It is built on [pyproject.nix](https://pyproject-nix.github.io/pyproject.nix) and [build-system-pkgs](https://github.com/pyproject-nix/build-system-pkgs).

**Docs:** https://pyproject-nix.github.io/uv2nix/
**Repo:** https://github.com/pyproject-nix/uv2nix

**Why uv2nix over alternatives:**
- Uses standard `pyproject.toml` and `uv.lock` — no Nix-specific lock formats
- Binary wheels work out of the box (auto-patched with `autoPatchelfHook`), minimizing override burden
- No bundled overrides to maintain (the design lesson from poetry2nix's maintainer burnout)
- Integrates with flake-parts, editable installs for dev shells, and cross-compilation

## When to use this skill

When creating a new Python project, CLI tool, or library that will be packaged with Nix. Do NOT use raw `pip`, `poetry`, or `python3.withPackages` for projects that need reproducible builds.

## Project setup

### 1. Bootstrap

```bash
nix-shell -p uv python3
uv init --app --package my-project
cd my-project
```

This creates:
```
my-project/
├── pyproject.toml
├── src/my_project/__init__.py
└── README.md
```

### 2. Configure pyproject.toml

```toml
[project]
name = "my-project"
version = "0.1.0"
description = "What this does"
requires-python = ">=3.12"
dependencies = [
    "requests",
]

[project.scripts]
my-project = "my_project.cli:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/my_project"]
```

Use `hatchling` as the build backend unless you have a reason not to. Define entry points under `[project.scripts]`.

### 3. Add dependencies and lock

```bash
uv add requests  # adds to pyproject.toml and updates uv.lock
uv lock          # regenerate lock file
```

### 4. Create flake.nix

```nix
{
  description = "My Python project";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, pyproject-nix, uv2nix, pyproject-build-systems, ... }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";  # use "sdist" if you need source builds
      };

      pythonSets = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        (pkgs.callPackage pyproject-nix.build.packages {
          python = pkgs.python3;
        }).overrideScope (
          lib.composeManyExtensions [
            pyproject-build-systems.overlays.wheel
            overlay
          ]
        )
      );
    in
    {
      packages = forAllSystems (system:
        let
          pythonSet = pythonSets.${system};
          pkgs = nixpkgs.legacyPackages.${system};
          mkApplication = (pkgs.callPackage pyproject-nix.build.util { }).mkApplication;
          venv = pythonSet.mkVirtualEnv "my-project-env" workspace.deps.default;
        in
        {
          default = (mkApplication {
            inherit venv;
            package = pythonSet.my-project;
          }).overrideAttrs {
            meta.mainProgram = "my-project";
          };
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pythonSet = pythonSets.${system};
          editableOverlay = workspace.mkEditablePyprojectOverlay {
            root = "$REPO_ROOT";
          };
          editableSet = pythonSet.overrideScope editableOverlay;
          venv = editableSet.mkVirtualEnv "dev-env" workspace.deps.all;
        in
        {
          default = pkgs.mkShell {
            packages = [ venv pkgs.uv ];
            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON = editableSet.python.interpreter;
              UV_PYTHON_DOWNLOADS = "never";
            };
            shellHook = ''
              unset PYTHONPATH
              export REPO_ROOT=$(git rev-parse --show-toplevel)
            '';
          };
        }
      );
    };
}
```

### 5. Build and test

```bash
git add -A          # flakes require tracked files
nix build           # builds the application
nix run             # runs the entry point
nix develop         # drops into dev shell with editable install
```

## Packaging for newt/brew overlay

When the project should be available system-wide but not public, put it in `~/newt/pkgs/<name>/` with a `package.nix` that takes uv2nix inputs:

```nix
# pkgs/my-project/package.nix
{ lib, callPackage, python3, pyproject-nix, uv2nix, pyproject-build-systems }:
let
  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
  overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
  pythonSet = (callPackage pyproject-nix.build.packages {
    python = python3;
  }).overrideScope (lib.composeManyExtensions [
    pyproject-build-systems.overlays.wheel
    overlay
  ]);
  venv = pythonSet.mkVirtualEnv "my-project-env" workspace.deps.default;
  mkApplication = (callPackage pyproject-nix.build.util { }).mkApplication;
in
mkApplication { inherit venv; package = pythonSet.my-project; }
```

Then wire it in `modules/<name>.nix` as `flake.overlays.<name>`.

## Wrapping non-Python runtime dependencies

If the Python app shells out to external tools (like `gh`, `ffmpeg`, etc.), wrap them:

```nix
app.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];
  postFixup = ''
    wrapProgram $out/bin/my-tool --prefix PATH : ${lib.makeBinPath [ gh ]}
  '';
});
```

## Common issues

- **Build fails for a wheel dependency:** add system libraries via `overrideAttrs` on the specific package in the python set
- **Missing build system:** `uv.lock` doesn't track build systems — `pyproject-build-systems` provides common ones, override manually for uncommon ones
- **`uv2nix_hammer_overrides`** is a third-party override collection for when `pyproject-build-systems` isn't enough
- **Source preference:** use `"wheel"` unless you need to patch a dependency, then override that specific package with `sourcePreference = "sdist"`

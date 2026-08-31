inputs: final: prev: {
  clan-cli = inputs.clan-core.packages.${prev.stdenv.hostPlatform.system}.clan-cli;
  hell = inputs.hell.packages.${prev.stdenv.hostPlatform.system}.default;
  tuicr = inputs.tuicr.packages.${prev.stdenv.hostPlatform.system}.default;

  # Signal with the dracula theme. The dracula org maintains the themed
  # rebuild (asar-injected CSS) in their flake.
  signal-desktop = (inputs.dracula-signal.overlays final prev).signal-desktop;

  # 0.8.3's rewritten PipeWire capture loop deadlocks once the consumer holds
  # both buffers of the pool, freezing every screencast after the first frame
  # (upstream issue emersion/xdg-desktop-portal-wlr#395; broke Zoom and
  # Chromium screen sharing on sway). Mirrors nixpkgs commit f9b78ed
  # ("xdg-desktop-portal-wlr: 0.8.3 -> 0.8.4"), already on master but not yet
  # in nixos-unstable. Drop once the channel includes it.
  xdg-desktop-portal-wlr = prev.xdg-desktop-portal-wlr.overrideAttrs (old: {
    version = "0.8.4";
    src = final.fetchFromGitHub {
      owner = "emersion";
      repo = "xdg-desktop-portal-wlr";
      rev = "v0.8.4";
      hash = "sha256-8Ohgkz13FcG8ddjjgreXkvFD2Q+zUDZnAM4Oh+C9P/s=";
    };
  });

  openjdk25-wakefield = prev.openjdk25.overrideAttrs (old: {
    pname = "openjdk-wakefield";
    version = "25.0.2";

    src = final.fetchFromGitHub {
      owner = "openjdk";
      repo = "wakefield";
      rev = "0bf2bd412d3323fa534be586b6f449fb77ea2e4c";
      hash = "sha256-vQlCarQVdyj6NRcIiYT1uMkYFLp6YjLPMwsOP+VC7ns=";
    };

    patches = old.patches ++ [ ./patches/jdk-xdg-open-support.patch ];

    nativeBuildInputs = old.nativeBuildInputs ++ [
      final.wayland-scanner
    ];

    buildInputs = (old.buildInputs or [ ]) ++ [
      final.wayland
      final.libxkbcommon
      final.wayland-protocols
    ];

    configureFlags = old.configureFlags ++ [
      "--with-wayland-include=${final.wayland.dev}/include"
      "--with-wayland-lib=${final.wayland.out}/lib"
      "--with-wayland-protocols=${final.wayland-protocols}/share/wayland-protocols"
      "--with-xkbcommon-include=${final.libxkbcommon.dev}/include"
      "--with-xkbcommon-lib=${final.libxkbcommon.out}/lib"
    ];
  });

  # ── WhisperLiveKit ───────────────────────────────────────────────

  ctranslate2-cuda = prev.ctranslate2.override {
    withCUDA = true;
    withCuDNN = true;
  };

  whisperlivekit = prev.callPackage ../pkgs/whisperlivekit { };
  whisperlivekit-chrome-extension = prev.callPackage ../pkgs/whisperlivekit-chrome-extension { };

  whisperlivekit-cuda =
    let
      ctranslate2-python-cuda = prev.python3Packages.ctranslate2.override {
        ctranslate2-cpp = final.ctranslate2-cuda;
      };
      faster-whisper-cuda = prev.python3Packages.faster-whisper.override {
        ctranslate2 = ctranslate2-python-cuda;
      };
    in
    prev.callPackage ../pkgs/whisperlivekit {
      cudaSupport = true;
      faster-whisper = faster-whisper-cuda;
    };

  whisperlivekit-server = prev.callPackage ../pkgs/whisperlivekit-server {
    whisperlivekit = final.whisperlivekit;
  };
  whisperlivekit-server-cuda = prev.callPackage ../pkgs/whisperlivekit-server {
    whisperlivekit = final.whisperlivekit-cuda;
    cudaSupport = true;
  };

  # ── JDK / Tooling ──────────────────────────────────────────────

  leiningen = prev.leiningen.override {
    jdk = final.openjdk25-wakefield;
  };

  emacs = prev.emacsWithPackagesFromUsePackage {
    config = builtins.toFile "emacs-config.el" (
      builtins.readFile ../configurations/emacs/emacs.el
      + "\n;; === newt proprietary config ===\n"
      + builtins.readFile "${inputs.newt}/configurations/emacs/newt.el"
    );
    alwaysEnsure = true;
    defaultInitFile = true;
    package = prev.emacs-unstable-pgtk;
    override =
      epkgs:
      let
        websocket = epkgs.elpaPackages.websocket.overrideAttrs (old: {
          packageRequires = (old.packageRequires or [ ]) ++ [ epkgs.melpaPackages.f ];
        });
        org-fc = epkgs.trivialBuild {
          pname = "org-fc";
          version = "20201121";
          src = prev.fetchFromGitHub {
            owner = "l3kn";
            repo = "org-fc";
            rev = "cc191458a991138bdba53328690a569b8b563502";
            sha256 = "sha256-wzMSgS4iZfpKOICqQQuQYNPb2h7i4tTWsMs7mVmgBt8=";
          };
          packageRequires = [
            epkgs.elpaPackages.org
            epkgs.melpaPackages.hydra
          ];
          propagatedUserEnvPkgs = with prev; [
            findutils
            gawk
          ];

          postInstall = ''
            cp -r ./awk/ $LISPDIR/
          '';

          meta = {
            description = "Spaced Repetition System for Emacs org-mode";
            license = prev.lib.licenses.gpl3;
          };
        };
        monet = epkgs.trivialBuild {
          pname = "monet";
          version = "0-unstable-2025-09-25";
          src = prev.fetchFromGitHub {
            owner = "stevemolitor";
            repo = "monet";
            rev = "72a18d372fef4b0971267bf13f127dcce681859a";
            sha256 = "sha256-3e5DIR+X6JLDaY7vRDutH3EAsyaqK3Jc73ugZTDRUrQ=";
          };
          packageRequires = [
            websocket
          ];

          meta = {
            description = "Implements Claude Code IDE protocol for Emacs";
            license = prev.lib.licenses.mit;
          };
        };
        # evil-ghostel ships in the ghostel repository and advises ghostel
        # functions that the native module implements, so a mismatched pair
        # signals wrong-number-of-arguments on every redraw.  MELPA versions
        # the two independently, while ghostel is a manual nixpkgs package:
        # build evil-ghostel from ghostel's source so the elisp and the
        # module always come from one tree.
        evil-ghostel = epkgs.melpaPackages.evil-ghostel.overrideAttrs {
          inherit (epkgs.ghostel) src version;
        };
        claude-code = epkgs.melpaPackages.claude-code.overrideAttrs (old: {
          src = prev.fetchFromGitHub {
            owner = "stevemolitor";
            repo = "claude-code.el";
            rev = "03199df8b3a1e9cd4857f0851f7a912ba524aff3";
            sha256 = "sha256-5QJrWIu4EgnHcOqMwlrs2JBBx7aI9OaSJswesr6Apfk=";
          };
          packageRequires = with epkgs; [
            eat
            melpaPackages.inheritenv
            melpaPackages.markdown-mode
            melpaPackages.projectile
            melpaPackages.transient
          ];
        });
      in
      epkgs
      // {
        inherit
          websocket
          org-fc
          monet
          claude-code
          evil-ghostel
          ;
      };
    extraEmacsPackages =
      epkgs: with epkgs; [
        use-package
        treesit-grammars.with-all-grammars
      ];
  };
}

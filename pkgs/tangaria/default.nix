{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  pkg-config,
  ncurses,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "tangaria";
  version = "0-unstable-2025-10-17";

  src = fetchFromGitHub {
    owner = "igroglaz";
    repo = "Tangaria";
    rev = "ccc5a03549";
    hash = "sha256-suMpu3nvwTphN3SSXDSXFeAH25x3r32oU1NwWLwuyMI=";
  };

  # Per the official tangaria-setup.sh, the build's installed lib must be
  # overlaid with files from Tangaria_release. These ship the gamedata
  # (class/monster/object tables) paired with the live server, so without
  # them the client and server disagree on indices and the protocol breaks.
  releaseSrc = fetchFromGitHub {
    owner = "igroglaz";
    repo = "Tangaria_release";
    rev = "76a5190593707db80c57f46d12486c7828ad1542";
    hash = "sha256-TNGdJ26WReruA1Si5R6f7JpEjLacI8x/gzNySWDW/AI=";
  };

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
  ];

  buildInputs = [
    ncurses
  ];

  configureFlags = [
    "--with-private-dirs"
    "--enable-release"
    "--enable-curses"
  ];

  enableParallelBuilding = true;

  postInstall = ''
    mkdir -p $out/bin
    ln -s $out/games/pwmangclient $out/bin/pwmangclient
    ln -s $out/games/pwmangband   $out/bin/pwmangband

    # Overlay Tangaria_release lib data — see tangaria-setup.sh:639-647.
    cp -Rf $releaseSrc/lib/customize $out/etc/pwmangband/
    cp -Rf $releaseSrc/lib/gamedata  $out/etc/pwmangband/
    for d in fonts help icons music screens sounds tiles; do
      cp -Rf $releaseSrc/lib/$d $out/share/pwmangband/
    done
  '';

  meta = {
    description = "Multiplayer ASCII roguelike based on PWMAngband";
    homepage = "https://tangaria.com/";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    mainProgram = "pwmangclient";
    maintainers = [ ];
  };
})

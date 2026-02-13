# Appgate SDP desktop client, based on upstream nixpkgs package.nix.
#
# Changes from upstream:
# - deps added to buildInputs so autoPatchelfHook writes RPATH entries
#   (upstream only used them in LD_LIBRARY_PATH wrappers)
# - runtimeDependencies for libudev (systemd dlopen)
# - appendRunpaths for GPU drivers, ICU, OpenSSL, and bundled .so's
# - LD_LIBRARY_PATH stripped from the appgate wrapper to avoid polluting
#   child processes (e.g. Firefox for SSO) with incompatible libraries
{
  addDriverRunpath,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  autoPatchelfHook,
  cairo,
  cups,
  curl,
  dbus,
  dnsmasq,
  dpkg,
  expat,
  fetchurl,
  gdk-pixbuf,
  glib,
  gtk3,
  icu,
  iproute2,
  krb5,
  lib,
  libdrm,
  libGL,
  libsecret,
  libuuid,
  libxcb,
  libxkbcommon,
  lttng-ust,
  makeWrapper,
  libgbm,
  networkmanager,
  nspr,
  nss,
  openssl,
  pango,
  python3,
  stdenv,
  systemd,
  xdg-utils,
  libxtst,
  libxscrnsaver,
  libxrender,
  libxrandr,
  libxi,
  libxfixes,
  libxext,
  libxdamage,
  libxcursor,
  libxcomposite,
  libx11,
  libxshmfence,
  libxkbfile,
  zlib,
}:

let
  deps = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    curl
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    icu
    krb5
    libdrm
    libsecret
    libuuid
    libxcb
    libxkbcommon
    lttng-ust
    libgbm
    nspr
    nss
    openssl
    pango
    stdenv.cc.cc
    systemd
    libx11
    libxscrnsaver
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxtst
    libxkbfile
    libxshmfence
    zlib
  ];
in
stdenv.mkDerivation rec {
  pname = "appgate-sdp";
  version = "6.5.0";

  src = fetchurl {
    url = "https://bin.appgate-sdp.com/${lib.versions.majorMinor version}/client/appgate-sdp_${version}_amd64.deb";
    sha256 = "sha256-VhqEjJHpXNdlrqqQzWLht15T746yAXCXWjAVtyMZI7k=";
  };

  # just patch interpreter
  autoPatchelfIgnoreMissingDeps = true;
  dontConfigure = true;
  dontBuild = true;

  # Upstream only lists python + dbus-python here. I add deps so
  # autoPatchelfHook resolves DT_NEEDED into proper RPATH entries
  # instead of relying on LD_LIBRARY_PATH at runtime.
  buildInputs = [
    python3
    python3.pkgs.dbus-python
  ]
  ++ deps;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    dpkg
  ];

  # systemd's libudev is dlopen'd at runtime, so autoPatchelfHook can't
  # discover it. runtimeDependencies adds it to RUNPATH directly.
  runtimeDependencies = [ systemd ];

  # Additional RUNPATH entries for libraries that aren't linked directly:
  # - $out/opt/appgate: bundled .so's shipped in the .deb
  # - driverLink: nvidia/mesa GPU drivers loaded at runtime
  # - libGL/icu/openssl: needed by the Chromium-based UI engine
  appendRunpaths = [
    "${placeholder "out"}/opt/appgate"
    "${addDriverRunpath.driverLink}/lib"
    "${lib.getLib libGL}/lib"
    "${lib.getLib icu}/lib"
    "${lib.getLib openssl}/lib"
  ];

  unpackPhase = ''
    dpkg-deb -x $src $out
  '';

  installPhase = ''
    cp -r $out/usr/share $out/share

    substituteInPlace $out/lib/systemd/system/appgate-dumb-resolver.service \
        --replace "/opt/" "$out/opt/"

    substituteInPlace $out/lib/systemd/system/appgatedriver.service \
        --replace "/opt/" "$out/opt/" \
        --replace "InaccessiblePaths=/mnt /srv /boot /media" "InaccessiblePaths=-/mnt -/srv -/boot -/media"

    substituteInPlace $out/lib/systemd/system/appgate-resolver.service \
        --replace "/usr/sbin/dnsmasq" "${dnsmasq}/bin/dnsmasq" \
        --replace "/opt/" "$out/opt/"

    substituteInPlace $out/opt/appgate/linux/nm.py \
        --replace "/usr/sbin/dnsmasq" "${dnsmasq}/bin/dnsmasq"

    substituteInPlace $out/opt/appgate/linux/set_dns \
        --replace "/etc/appgate.conf" "$out/etc/appgate.conf"

    wrapProgram $out/opt/appgate/service/createdump \
        --set LD_LIBRARY_PATH "${lib.makeLibraryPath [ stdenv.cc.cc ]}"

    wrapProgram $out/opt/appgate/appgate-driver \
        --prefix PATH : ${
          lib.makeBinPath [
            iproute2
            networkmanager
            dnsmasq
          ]
        } \
        --set LD_LIBRARY_PATH $out/opt/appgate/service

    # make xdg-open overrideable at runtime.
    # Unlike upstream, we intentionally omit --set LD_LIBRARY_PATH here;
    # the wrapper would leak it into child processes (Firefox, xdg-open),
    # causing them to load incompatible bundled libs and crash.
    # RPATH entries above handle library resolution instead.
    makeWrapper $out/opt/appgate/Appgate $out/bin/appgate \
        --suffix PATH : ${lib.makeBinPath [ xdg-utils ]}
  '';

  # autoPatchelfHook may re-add LD_LIBRARY_PATH to wrappers; strip it
  # from the user-facing appgate wrapper so child processes stay clean.
  postFixup = ''
    sed -i '/^export LD_LIBRARY_PATH=/d' $out/bin/appgate
  '';

  meta = {
    description = "Appgate SDP (Software Defined Perimeter) desktop client";
    homepage = "https://www.appgate.com/support/software-defined-perimeter-support";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
    maintainers = with lib.maintainers; [ ymatsiuk ];
    mainProgram = "appgate";
  };
}

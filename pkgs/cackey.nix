{
  lib,
  stdenv,
  fetchurl,
  zlib,
  pcsclite,
}:
stdenv.mkDerivation rec {
  name = "cackey";
  version = "0.7.11";
  src = fetchurl {
    url = "http://cackey.rkeene.org/download/${version}/cackey-${version}.tar.gz";
    hash = "sha256-DtRZgU+0dT9uX6gANMVdGzEvVfiO5zF0Rt/0n6blcPM=";
  };
  buildInputs = [
    zlib
    pcsclite
  ];
  configureFlags = [
    "--with-pcsc-headers=${lib.getDev pcsclite}/include/PCSC/"
    "--with-pcsc-libs=${lib.getLib pcsclite}/lib/libpcsclite.so"
  ];
}

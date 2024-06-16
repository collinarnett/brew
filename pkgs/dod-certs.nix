{
  stdenv,
  fetchzip,
  openssl,
  unzip,
}:
stdenv.mkDerivation {
  pname = "dod-certs";
  version = "0.1.0";

  src = fetchzip {
    url = "https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip";
    sha256 = "sha256-QgRw3UPTTXNadkpo5FonQ6hTsQVnk6l/2n2hnLOaL1E=";
  };

  nativeBuildInputs = [unzip openssl];

  buildPhase = ''
    openssl pkcs7 -in certificates_pkcs7_v5_13_dod_der.p7b -inform der -print_certs -out dod_CAs.pem
  '';

  installPhase = ''
    mkdir $out
    cp dod_CAs.pem $out/dod-certs.pem
  '';
}

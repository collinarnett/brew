{
  stdenv,
  fetchzip,
  openssl,
  unzip,
}:
stdenv.mkDerivation {
  pname = "dod-certs";
  version = "5.14.0";

  src = fetchzip {
    url = "https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip";
    sha256 = "sha256-HhbGyHgwV8bbZutDqhHriso3y84XxumtuED9BHO0XEk=";
  };

  nativeBuildInputs = [unzip openssl];

  buildPhase = ''
    ls
    openssl pkcs7 -in Certificates_PKCS7_v5_14_DoD.der.p7b -inform der -print_certs -out dod_CAs.pem
  '';

  installPhase = ''
    mkdir $out
    cp dod_CAs.pem $out/dod-certs.pem
  '';
}

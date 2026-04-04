{ pkgs ? import <nixpkgs> { } }:

let
  codegenSrc = pkgs.fetchFromGitHub {
    owner = "Haskell-OpenAPI-Code-Generator";
    repo = "Haskell-OpenAPI-Client-Code-Generator";
    rev = "c01eecc888c173da754687746f78fda03efe33fc";
    sha256 = "0d3n18h84nqh2xsq9c0k88dlh2gwb407hcvk4v2alv3yvryg3zw6";
  };

  codegen = pkgs.haskellPackages.callCabal2nix
    "openapi3-code-generator" (codegenSrc + "/openapi3-code-generator") { };

  brokenModules = [
    "Delete_objects__entity___objectId_"
    "Get_objects__entity_"
    "Get_objects__entity___objectId_"
    "Get_userfields__entity___objectId_"
    "Post_objects__entity_"
    "Put_objects__entity___objectId_"
    "Put_userfields__entity___objectId_"
  ];
in
pkgs.runCommand "grocy-client-src" {
  nativeBuildInputs = [ codegen pkgs.glibcLocales ];
  LANG = "en_US.UTF-8";
  LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
} ''
  openapi3-code-generator-exe \
    ${pkgs.grocy.src}/grocy.openapi.json \
    --output-dir $out \
    --module-name GrocyClient

  # Remove modules broken by missing ExposedEntity schemas in Grocy's spec
  ${builtins.concatStringsSep "\n" (
    map (m: "rm -f $out/src/GrocyClient/Operations/${m}.hs") brokenModules
  )}
  sed -i '/${builtins.concatStringsSep "\\|" brokenModules}/d' $out/src/GrocyClient.hs

  rm -f $out/openapi.cabal $out/stack.yaml

  modules=$(find $out/src -name '*.hs' ! -name '*.hs-boot' \
    | sed "s|$out/src/||; s|/|.|g; s|\.hs$||" \
    | sort \
    | awk 'NR==1{printf "      %s\n",$0} NR>1{printf "    , %s\n",$0}')

  cat > $out/grocy-client.cabal << CABAL
  cabal-version: 1.12
  name:           grocy-client
  version:        0.1.0
  synopsis:       Generated Grocy REST API client (Grocy ${pkgs.lib.getVersion pkgs.grocy})
  license:        MIT
  build-type:     Simple

  library
    exposed-modules:
  $modules
    hs-source-dirs: src
    build-depends:
        base >=4.7 && <5
      , text
      , ghc-prim
      , http-conduit
      , http-client
      , http-types
      , bytestring
      , aeson
      , unordered-containers
      , vector
      , scientific
      , time
      , mtl
      , transformers
    default-language: Haskell2010
  CABAL
''

final: prev:
let
  localHsPkg = hprev: name: hprev.callCabal2nix name ./${name} { };
  localHsPkgNames = [
    "browser-cookies"
    "walmart"
    "walmart-extractor"
    "grocy-client"
    "walmart-grocy-import"
  ];
in
{
  appgate-sdp = prev.callPackage ./appgate-sdp.nix { }; # fixes RPATH/LD_LIBRARY_PATH over upstream
  dod-certs = prev.callPackage ./dod-certs.nix { };
  cackey = prev.callPackage ./cackey.nix { };
  gitlab-mcp = prev.callPackage ./gitlab-mcp.nix { };
  iommu-groups = prev.callPackage ./iommu-groups.nix { };
  lightpanda = prev.callPackage ./lightpanda { };
  haskellPackages = prev.haskellPackages.override {
    overrides = hfinal: hprev: prev.lib.genAttrs localHsPkgNames (localHsPkg hprev);
  };
  walmart-grocy-import =
    let
      exe = prev.haskell.lib.compose.justStaticExecutables
        final.haskellPackages.walmart-grocy-import;
    in
    exe.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
      postFixup = (old.postFixup or "") + ''
        wrapProgram $out/bin/walmart-grocy-import \
          --prefix PATH : ${prev.lib.makeBinPath [ final.lightpanda ]}
      '';
    });
  walmart-extractor =
    let
      exe = prev.haskell.lib.compose.justStaticExecutables
        final.haskellPackages.walmart-extractor;
    in
    exe.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
      postFixup = (old.postFixup or "") + ''
        wrapProgram $out/bin/walmart-extractor \
          --prefix PATH : ${prev.lib.makeBinPath [ final.lightpanda ]}
      '';
    });
}

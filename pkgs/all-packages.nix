final: prev: {
  appgate-sdp = prev.callPackage ./appgate-sdp.nix { }; # fixes RPATH/LD_LIBRARY_PATH over upstream
  dod-certs = prev.callPackage ./dod-certs.nix { };
  cackey = prev.callPackage ./cackey.nix { };
  gitlab-mcp = prev.callPackage ./gitlab-mcp.nix { };
  iommu-groups = prev.callPackage ./iommu-groups.nix { };
  lightpanda = prev.callPackage ./lightpanda { };
  walmart-grocy-import =
    let
      drv = prev.haskellPackages.callCabal2nix
        "walmart-grocy-import" ./walmart-grocy-import { };
      exe = prev.haskell.lib.compose.justStaticExecutables drv;
    in
    exe.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
      postFixup = (old.postFixup or "") + ''
        wrapProgram $out/bin/walmart-grocy-import \
          --prefix PATH : ${prev.lib.makeBinPath [ final.lightpanda ]}
      '';
    });
}

final: prev: {
  appgate-sdp = prev.callPackage ./appgate-sdp.nix { }; # fixes RPATH/LD_LIBRARY_PATH over upstream
  dod-certs = prev.callPackage ./dod-certs.nix { };
  cackey = prev.callPackage ./cackey.nix { };
  iommu-groups = prev.callPackage ./iommu-groups.nix { };
}

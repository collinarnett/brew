final: prev:
let
  localHsPkg = hprev: name: hprev.callCabal2nix name ./${name} { };
  localHsPkgNames = [
    "browser-cookies"
    "clan-mcp"
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
  clan-commands-json = prev.callPackage ./clan-commands-json.nix { };
  clan-mcp-wrapped =
    let
      exe = prev.haskell.lib.compose.justStaticExecutables final.haskellPackages.clan-mcp;
    in
    exe.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
      postFixup = (old.postFixup or "") + ''
        wrapProgram $out/bin/clan-mcp \
          --add-flags "${final.clan-commands-json}/share/clan-mcp/commands.json" \
          --prefix PATH : ${prev.lib.makeBinPath [ prev.clan-cli ]}
      '';
    });
  gitlab-mcp = prev.callPackage ./gitlab-mcp.nix { };
  gpt-oss-20b-heretic-ara-v4 = prev.callPackage ./gpt-oss-20b-heretic-ara-v4 { };
  iommu-groups = prev.callPackage ./iommu-groups.nix { };
  lightpanda = prev.callPackage ./lightpanda { };
  mcp-conformance = prev.callPackage ./mcp-conformance { };
  recap-triage = prev.callPackage ./recap-triage { };
  tangaria = prev.callPackage ./tangaria { };
  haskellPackages = prev.haskellPackages.override {
    overrides =
      hfinal: hprev:
      prev.lib.genAttrs localHsPkgNames (localHsPkg hprev)
      // {
        mcp-server = hprev.callCabal2nix "mcp-server" (prev.fetchFromGitHub {
          owner = "collinarnett";
          repo = "haskell-mcp-server";
          rev = "af15fc736073ac2ed0d16f382b76db9cdc590e75";
          hash = "sha256-tolMEGXH5ao6Ay9ePpKVuj0j3ALa6fDuLDHhttQDYL4=";
        }) { };
      };
  };
  walmart-grocy-import =
    let
      exe = prev.haskell.lib.compose.justStaticExecutables final.haskellPackages.walmart-grocy-import;
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
      exe = prev.haskell.lib.compose.justStaticExecutables final.haskellPackages.walmart-extractor;
    in
    exe.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
      postFixup = (old.postFixup or "") + ''
        wrapProgram $out/bin/walmart-extractor \
          --prefix PATH : ${prev.lib.makeBinPath [ final.lightpanda ]}
      '';
    });
}

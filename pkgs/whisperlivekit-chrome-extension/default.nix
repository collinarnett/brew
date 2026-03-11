{
  stdenvNoCC,
  fetchFromGitHub,
  openssl,
  zip,
  python3,
  jq,
}:

stdenvNoCC.mkDerivation {
  pname = "whisperlivekit-chrome-extension";
  version = "0.2.19";

  src = fetchFromGitHub {
    owner = "QuentinFuxa";
    repo = "WhisperLiveKit";
    tag = "v0.2.19";
    hash = "sha256-QC/XMuEURI/I9GmX38LCH0fmC++vo94FEeWKmma6vnw=";
  };

  signingKey = ./key.pem;

  nativeBuildInputs = [
    openssl
    zip
    python3
    jq
  ];

  packCrx = builtins.toFile "pack_crx.py" ''
    import struct, sys

    with open('pub.der', 'rb') as f:
        pubkey = f.read()
    with open('sig.der', 'rb') as f:
        sig = f.read()
    with open('extension.zip', 'rb') as f:
        zipdata = f.read()

    with open('whisperlivekit.crx', 'wb') as f:
        f.write(b'Cr24')
        f.write(struct.pack('<I', 2))
        f.write(struct.pack('<I', len(pubkey)))
        f.write(struct.pack('<I', len(sig)))
        f.write(pubkey)
        f.write(sig)
        f.write(zipdata)
  '';

  computeId = builtins.toFile "compute_id.py" ''
    import hashlib

    with open('pub.der', 'rb') as f:
        pubkey = f.read()

    digest = hashlib.sha256(pubkey).hexdigest()
    ext_id = "".join(chr(ord('a') + int(c, 16)) for c in digest[:32])
    print(ext_id, end="")
  '';

  buildPhase = ''
        runHook preBuild

        # Assemble extension directory
        mkdir -p ext/icons ext/web/src

        # Extension-specific files
        cp chrome-extension/manifest.json ext/
        cp chrome-extension/background.js ext/
        cp chrome-extension/sidepanel.js ext/
        cp chrome-extension/requestPermissions.html ext/
        cp chrome-extension/requestPermissions.js ext/
        cp chrome-extension/icons/* ext/icons/

        # Sync web frontend files (replicates scripts/sync_extension.py)
        cp whisperlivekit/web/live_transcription.html ext/
        cp whisperlivekit/web/live_transcription.js ext/
        cp whisperlivekit/web/live_transcription.css ext/
        cp whisperlivekit/web/src/system_mode.svg ext/web/src/
        cp whisperlivekit/web/src/light_mode.svg ext/web/src/
        cp whisperlivekit/web/src/dark_mode.svg ext/web/src/
        cp whisperlivekit/web/src/settings.svg ext/web/src/

        # Add managed storage schema for enterprise policy support
        cat > ext/managed_schema.json << 'SCHEMA'
        {
          "type": "object",
          "properties": {
            "websocketUrl": {
              "type": "string",
              "description": "WebSocket URL for the WhisperLiveKit server"
            }
          }
        }
        SCHEMA

        # Patch manifest.json to reference managed storage schema
        jq '. + {"storage": {"managed_schema": "managed_schema.json"}}' ext/manifest.json > ext/manifest.json.tmp
        mv ext/manifest.json.tmp ext/manifest.json

        # Patch live_transcription.js to read managed storage policy
        cat > managed_storage_patch.js << 'PATCH'
      if (isExtension && chrome.storage && chrome.storage.managed) {
        chrome.storage.managed.get("websocketUrl", (result) => {
          if (result && result.websocketUrl) {
            websocketUrl = result.websocketUrl;
            websocketInput.value = websocketUrl;
            if (websocketDefaultSpan) websocketDefaultSpan.textContent = websocketUrl;
          }
        });
      }
    PATCH
        sed -i '/websocketUrl = defaultWebSocketUrl;/r managed_storage_patch.js' ext/live_transcription.js

        # Create zip of extension directory
        (cd ext && zip -r -X ../extension.zip .)

        # Extract DER public key from PEM private key
        openssl rsa -in "$signingKey" -pubout -outform DER -out pub.der 2>/dev/null

        # Sign the zip with SHA1-RSA
        openssl dgst -sha1 -sign "$signingKey" -out sig.der extension.zip

        # Build CRX2 file
        python3 "$packCrx"

        # Compute extension ID
        python3 "$computeId" > extension-id

        runHook postBuild
  '';

  passthru.extensionId = "nhnakplebgmjlfejkadcbdchmfglljki";

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp whisperlivekit.crx $out/whisperlivekit.crx
    cp extension-id $out/extension-id

    runHook postInstall
  '';
}

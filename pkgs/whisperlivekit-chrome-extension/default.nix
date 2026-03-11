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

  # CRX3 packing: two-phase process.
  # Phase 1: build SignedData protobuf and the payload that gets signed.
  # Phase 2 (after openssl signs the payload): assemble the final CRX3 file.
  prepareCrx3 = builtins.toFile "prepare_crx3.py" ''
    import struct, hashlib

    def varint(value):
        out = []
        while value > 0x7F:
            out.append((value & 0x7F) | 0x80)
            value >>= 7
        out.append(value)
        return bytes(out)

    def field(num, data):
        return varint((num << 3) | 2) + varint(len(data)) + data

    with open('pub.der', 'rb') as f:
        pubkey = f.read()
    with open('extension.zip', 'rb') as f:
        zipdata = f.read()

    crx_id = hashlib.sha256(pubkey).digest()[:16]
    signed_header_data = field(1, crx_id)

    with open('signed_header_data.bin', 'wb') as f:
        f.write(signed_header_data)

    # Payload to sign: "CRX3 SignedData\x00" + le32(len) + signed_header_data + zip
    with open('payload.bin', 'wb') as f:
        f.write(b"CRX3 SignedData\x00")
        f.write(struct.pack('<I', len(signed_header_data)))
        f.write(signed_header_data)
        f.write(zipdata)
  '';

  assembleCrx3 = builtins.toFile "assemble_crx3.py" ''
    import struct

    def varint(value):
        out = []
        while value > 0x7F:
            out.append((value & 0x7F) | 0x80)
            value >>= 7
        out.append(value)
        return bytes(out)

    def field(num, data):
        return varint((num << 3) | 2) + varint(len(data)) + data

    with open('pub.der', 'rb') as f:
        pubkey = f.read()
    with open('sig.der', 'rb') as f:
        sig = f.read()
    with open('signed_header_data.bin', 'rb') as f:
        signed_header_data = f.read()
    with open('extension.zip', 'rb') as f:
        zipdata = f.read()

    proof = field(1, pubkey) + field(2, sig)
    header = field(2, proof) + field(10000, signed_header_data)

    with open('whisperlivekit.crx', 'wb') as f:
        f.write(b'Cr24')
        f.write(struct.pack('<I', 3))
        f.write(struct.pack('<I', len(header)))
        f.write(header)
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

  managedSchema = builtins.toFile "managed_schema.json" (builtins.toJSON {
    type = "object";
    properties.websocketUrl = {
      type = "string";
      description = "WebSocket URL for the WhisperLiveKit server";
    };
  });

  managedStoragePatch = builtins.toFile "managed_storage_patch.js" ''
    if (isExtension && chrome.storage && chrome.storage.managed) {
      chrome.storage.managed.get("websocketUrl", (result) => {
        if (result && result.websocketUrl) {
          websocketUrl = result.websocketUrl;
          websocketInput.value = websocketUrl;
          if (websocketDefaultSpan) websocketDefaultSpan.textContent = websocketUrl;
        }
      });
    }
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
    cp "$managedSchema" ext/managed_schema.json

    # Patch manifest.json to reference managed storage schema
    jq --arg v "$version" '. + {"version": $v, "storage": {"managed_schema": "managed_schema.json"}}' ext/manifest.json > ext/manifest.json.tmp
    mv ext/manifest.json.tmp ext/manifest.json

    # Patch live_transcription.js to read managed storage policy
    sed -i '/websocketUrl = defaultWebSocketUrl;/r '"$managedStoragePatch" ext/live_transcription.js

    # Create zip of extension directory
    (cd ext && zip -r -X ../extension.zip .)

    # Extract DER public key from PEM private key
    openssl rsa -in "$signingKey" -pubout -outform DER -out pub.der 2>/dev/null

    # Build CRX3: prepare signed-header protobuf and payload to sign
    python3 "$prepareCrx3"

    # Sign the payload with RSA PKCS#1 v1.5 SHA-256
    openssl dgst -sha256 -sign "$signingKey" -out sig.der payload.bin

    # Assemble the final CRX3 file
    python3 "$assembleCrx3"

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

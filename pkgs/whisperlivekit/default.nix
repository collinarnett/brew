{
  lib,
  python3Packages,
  fetchFromGitHub,
  ffmpeg,
  addDriverRunpath,
  cudaSupport ? false,
  faster-whisper ? python3Packages.faster-whisper,
}:

python3Packages.buildPythonPackage rec {
  pname = "whisperlivekit";
  version = "0.2.19";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "QuentinFuxa";
    repo = "WhisperLiveKit";
    tag = "v${version}";
    hash = "sha256-QC/XMuEURI/I9GmX38LCH0fmC++vo94FEeWKmma6vnw=";
  };

  patches = [ ./fix-storageview-conversion.patch ];

  build-system = [ python3Packages.setuptools ];

  pythonRemoveDeps = [ "torchaudio" ];

  dependencies = [
    python3Packages.fastapi
    python3Packages.huggingface-hub
    python3Packages.librosa
    python3Packages.soundfile
    python3Packages.tiktoken
    python3Packages.tqdm
    python3Packages.uvicorn
    python3Packages.websockets
    faster-whisper
    python3Packages.torch
  ];

  makeWrapperArgs =
    [
      "--prefix PATH : ${lib.makeBinPath [ ffmpeg ]}"
    ]
    ++ lib.optionals cudaSupport [
      "--suffix LD_LIBRARY_PATH : ${addDriverRunpath.driverLink}/lib"
    ];

  pythonImportsCheck = [ "whisperlivekit" ];

  # no tests in the release tarball
  doCheck = false;

  meta = {
    description = "Real-time speech-to-text with speaker diarization using Whisper";
    homepage = "https://github.com/QuentinFuxa/WhisperLiveKit";
    license = lib.licenses.mit;
    mainProgram = "whisperlivekit-server";
  };
}

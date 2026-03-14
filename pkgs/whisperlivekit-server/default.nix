{
  lib,
  writeShellApplication,
  python3,
  whisperlivekit,
  ffmpeg,
  addDriverRunpath,
  cudaSupport ? false,
}:

let
  pythonEnv = python3.withPackages (_: [ whisperlivekit ]);
in
writeShellApplication {
  name = "whisperlivekit-server";
  runtimeInputs = [ ffmpeg ];
  text = ''
    ${lib.optionalString cudaSupport ''export LD_LIBRARY_PATH="${addDriverRunpath.driverLink}/lib:''${LD_LIBRARY_PATH:-}"''}
    exec ${pythonEnv}/bin/python ${./server.py} "$@"
  '';
}

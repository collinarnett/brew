# p-e-w/gpt-oss-20b-heretic-ara-v4 → MXFP4_MOE GGUF → ollama Modelfile,
# built entirely from a single git-LFS fetch + llama.cpp tooling.
# `passthru` exposes every intermediate so each stage can be built
# independently via `nix build .#gpt-oss-20b-heretic-ara-v4.<attr>`.
{
  lib,
  fetchgit,
  llama-cpp,
  python3,
  runCommand,
  writeShellApplication,
}:

let
  # Mirrors upstream llama.cpp's `.devops/nix/python-scripts.nix` deps
  # plus what gguf-py pulls in transitively (mistral-common →
  # pydantic-extra-types → pycountry).
  pythonEnv = python3.withPackages (
    ps: with ps; [
      gguf
      mistral-common
      numpy
      protobuf
      pycountry
      pyyaml
      safetensors
      sentencepiece
      torch
      tqdm
      transformers
    ]
  );

  # convert_hf_to_gguf.py from the same llama.cpp source that nixpkgs
  # builds llama-quantize from — keeps gguf-py and the C++ binaries on
  # the same version.
  llama-convert-hf-to-gguf = writeShellApplication {
    name = "llama-convert-hf-to-gguf";
    runtimeInputs = [ pythonEnv ];
    text = ''exec python ${llama-cpp.src}/convert_hf_to_gguf.py "$@"'';
  };

  # Single fixed-output derivation pulling the whole HF repo — git plus
  # LFS blobs. One hash protects the entire source tree.
  #
  # NOTE: replace lib.fakeHash with the real hash on first build. Nix
  # reports the actual value in the "hash mismatch" error message.
  source = fetchgit {
    url = "https://huggingface.co/p-e-w/gpt-oss-20b-heretic-ara-v4";
    rev = "main";
    fetchLFS = true;
    hash = lib.fakeHash;
  };

  # Strip the doubled `_blocks_blocks` / `_blocks_scales` suffixes ara-v4
  # weights ship with — the converter's substring match treats the 3D
  # scales tensors as 4D blocks otherwise and crashes.
  renamedSafetensors =
    runCommand "gpt-oss-20b-heretic-ara-v4-renamed.safetensors"
      {
        nativeBuildInputs = [ pythonEnv ];
      }
      ''
        python ${./rename-tensors.py} ${source}/model.safetensors $out
      '';

  # F16 GGUF intermediate. The MoE block tensors keep raw_dtype = mxfp4
  # — the converter's gpt-oss path passes them through verbatim — so
  # only norms and embeddings are actually f16 in this file.
  f16Gguf =
    runCommand "gpt-oss-20b-heretic-ara-v4-f16.gguf"
      {
        nativeBuildInputs = [ llama-convert-hf-to-gguf ];
      }
      ''
        mkdir hf
        # Symlink every config/tokenizer file from the source repo, then
        # swap in the renamed safetensors.
        for f in ${source}/*; do
          name=$(basename "$f")
          case "$name" in
            model.safetensors|.git|.gitattributes|README.md) ;;
            *) ln -s "$f" "hf/$name" ;;
          esac
        done
        ln -s ${renamedSafetensors} hf/model.safetensors
        llama-convert-hf-to-gguf hf --outfile $out --outtype f16
      '';

  gguf =
    runCommand "gpt-oss-20b-heretic-ara-v4.gguf"
      {
        nativeBuildInputs = [ llama-cpp ];
      }
      ''
        llama-quantize ${f16Gguf} $out MXFP4_MOE
      '';
in

# Final output is the Modelfile (a single text file whose contents
# reference the GGUF via its store path). `ollama create -f $out`
# consumes it; Nix tracks the GGUF as a runtime dependency via the
# string reference.
runCommand "gpt-oss-20b-heretic-ara-v4-Modelfile"
  {
    passthru = {
      inherit
        gguf
        f16Gguf
        renamedSafetensors
        source
        ;
    };
  }
  ''
    sed "s|@GGUF@|${gguf}|" ${./Modelfile} > $out
  ''

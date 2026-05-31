# p-e-w/gpt-oss-20b-heretic-ara-v4 → MXFP4_MOE GGUF → ollama Modelfile,
# built from per-file fetchurl downloads + llama.cpp tooling.
# `passthru` exposes every intermediate so each stage can be built
# independently via `nix build .#gpt-oss-20b-heretic-ara-v4.<attr>`.
{
  lib,
  fetchurl,
  llama-cpp,
  python3,
  runCommand,
  writeShellApplication,
}:

let
  hfRepo = "p-e-w/gpt-oss-20b-heretic-ara-v4";

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

  # convert_hf_to_gguf.py from the same llama.cpp source nixpkgs builds
  # llama-quantize from — keeps gguf-py and the C++ binaries on the same
  # version.
  llama-convert-hf-to-gguf = writeShellApplication {
    name = "llama-convert-hf-to-gguf";
    runtimeInputs = [ pythonEnv ];
    text = ''exec python ${llama-cpp.src}/convert_hf_to_gguf.py "$@"'';
  };

  # One fetchurl per HF file. HF rejects the default curl UA, so spoof
  # Wget — same trick nixpkgs' hasktorch datasets use.
  hfFile =
    file: hash:
    fetchurl {
      url = "https://huggingface.co/${hfRepo}/resolve/main/${file}";
      inherit hash;
      curlOptsList = [ "-HUser-Agent: Wget/1.21.4" ];
    };

  safetensors = hfFile "model.safetensors" "sha256-ScpBoGyYdQiWWZol9Iqxq5LH2mGiY7KT7vTR+z+ZO7w=";
  configJson = hfFile "config.json" "sha256-69Wacmbh52cKnvMonsqDBunOrxfsupIpFploRjX//gY=";
  generationConfig = hfFile "generation_config.json" "sha256-jbMFb7T444/T6kTf3T5fzc+GeyLGtcbvzH8FPq24gYA=";
  tokenizerJson = hfFile "tokenizer.json" "sha256-BhT+g8ratCEpbmZOH0j0Jh+o/vbgPmO7dcIPOON9B9M=";
  tokenizerConfig = hfFile "tokenizer_config.json" "sha256-/OBl8I3KpvjluAvtfFGVS/fM+hwsED/TbxsNZxUx8Uo=";
  chatTemplate = hfFile "chat_template.jinja" "sha256-pMmRnLvUrN1RzP/iLaBJJksbc+WQVfpYgRqZ7718gUY=";

  # Strip the doubled `_blocks_blocks` / `_blocks_scales` suffixes ara-v4
  # weights ship with — the converter's substring match treats the 3D
  # scales tensors as 4D blocks otherwise and crashes.
  renamedSafetensors =
    runCommand "gpt-oss-20b-heretic-ara-v4-renamed.safetensors"
      {
        nativeBuildInputs = [ pythonEnv ];
      }
      ''
        python ${./rename-tensors.py} ${safetensors} $out
      '';

  # Assemble the HF source layout convert_hf_to_gguf.py expects.
  source = runCommand "gpt-oss-20b-heretic-ara-v4-source" { } ''
    mkdir $out
    ln -s ${configJson}         $out/config.json
    ln -s ${generationConfig}   $out/generation_config.json
    ln -s ${tokenizerJson}      $out/tokenizer.json
    ln -s ${tokenizerConfig}    $out/tokenizer_config.json
    ln -s ${chatTemplate}       $out/chat_template.jinja
    ln -s ${renamedSafetensors} $out/model.safetensors
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
        llama-convert-hf-to-gguf ${source} --outfile $out --outtype f16
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
        safetensors
        source
        ;
    };
  }
  ''
    sed "s|@GGUF@|${gguf}|" ${./Modelfile} > $out
  ''

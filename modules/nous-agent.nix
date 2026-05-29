{ inputs, ... }:
{
  flake.modules.nixos.nous-agent =
    { config, lib, ... }:
    let
      cfg = config.brew.nous-agent;
    in
    {
      imports = [ inputs.hermes-agent.nixosModules.default ];

      options.brew.nous-agent = {
        enable = lib.mkEnableOption "nous-agent (Hermes Agent)";
        users = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Users granted shared access to the hermes-agent stateDir by
            being added to the hermes group. Mirrors upstream's
            container.hostUsers but for native (non-container) mode.
          '';
        };
        modelHost = lib.mkOption {
          type = lib.types.str;
          default = "vampire.clan";
          description = "Host running the ollama backend.";
        };
        modelPort = lib.mkOption {
          type = lib.types.port;
          default = 11434;
        };
        model = lib.mkOption {
          type = lib.types.str;
          default = "gpt-oss-heretic-ara-v4:20b";
          description = ''
            Ollama model tag served by modelHost. The heretic-ara-v4
            variant is created out-of-band on vampire via
            ollama create from a custom Modelfile that pairs the
            MXFP4-quantized GGUF (built from p-e-w/gpt-oss-20b-heretic-ara-v4
            safetensors) with the official gpt-oss:20b Harmony chat template
            plus a stop sequence at <|call|> so ollama can extract
            structured tool_calls.
          '';
        };
        contextLength = lib.mkOption {
          type = lib.types.int;
          default = 65536;
          description = ''
            Must be <= OLLAMA_CONTEXT_LENGTH on the model host and >= 64K
            (Hermes Agent's minimum). 14B Q4 + 64K q8_0 KV cache fits
            comfortably on a 24 GB GPU.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        services.hermes-agent = {
          enable = true;
          addToSystemPackages = true;
          settings.model = {
            provider = "custom";
            default = cfg.model;
            base_url = "http://${cfg.modelHost}:${toString cfg.modelPort}/v1";
            context_length = cfg.contextLength;
          };
        };

        users.users = lib.genAttrs cfg.users (_: {
          extraGroups = [ config.services.hermes-agent.group ];
        });
      };
    };
}

{ ... }:
let
  audioOutputOptions =
    { lib, ... }:
    {
      options.brew.audio-output = {
        enable = lib.mkEnableOption "waybar audio output switcher";
        outputs = lib.mkOption {
          description = ''
            Curated audio outputs for the waybar switcher. Each entry maps a
            friendly label to a sink, optionally switching an ALSA card profile
            first (needed when outputs are mutually-exclusive profiles on one
            codec, e.g. analog line-out vs. optical S/PDIF).
          '';
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                label = lib.mkOption {
                  type = lib.types.str;
                  description = "Menu label, e.g. \"Speakers\".";
                };
                icon = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Glyph shown in the bar and menu.";
                };
                sink = lib.mkOption {
                  type = lib.types.str;
                  description = "PipeWire sink node name to make default.";
                };
                card = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "ALSA card to switch profile on, if a profile change is needed.";
                };
                profile = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Card profile to activate before selecting the sink.";
                };
              };
            }
          );
        };
      };
    };
in
{
  flake.modules.nixos.audio-output =
    { config, lib, ... }:
    let
      cfg = config.brew.audio-output;
    in
    {
      imports = [ audioOutputOptions ];
      config = lib.mkIf cfg.enable {
        home-manager.sharedModules = [
          {
            brew.audio-output = {
              enable = true;
              inherit (cfg) outputs;
            };
          }
        ];
      };
    };

  flake.modules.homeManager.audio-output =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.audio-output;
      mkArr = f: "(" + lib.concatMapStringsSep " " (o: lib.escapeShellArg (f o)) cfg.outputs + ")";
      audioOutput = pkgs.writeShellApplication {
        name = "audio-output";
        runtimeInputs = with pkgs; [
          pulseaudio
          wofi
          procps
          coreutils
        ];
        text = ''
          LABELS=${mkArr (o: o.label)}
          ICONS=${mkArr (o: o.icon)}
          SINKS=${mkArr (o: o.sink)}
          CARDS=${mkArr (o: if o.card == null then "" else o.card)}
          PROFILES=${mkArr (o: if o.profile == null then "" else o.profile)}
          N=''${#SINKS[@]}

          current=$(pactl get-default-sink 2>/dev/null || true)
          idx=-1
          for (( i=0; i<N; i++ )); do
            if [[ ''${SINKS[i]} == "$current" ]]; then
              idx=$i
              break
            fi
          done

          case ''${1:-status} in
            status)
              if (( idx >= 0 )); then
                printf '{"text":"%s","tooltip":"Output: %s","class":"audio-output"}\n' \
                  "''${ICONS[idx]}" "''${LABELS[idx]}"
              else
                printf '{"text":"%s","tooltip":"Output: %s","class":"audio-output unknown"}\n' \
                  "?" "$current"
              fi
              ;;
            menu)
              choice=$(
                for (( i=0; i<N; i++ )); do
                  if [[ -n ''${ICONS[i]} ]]; then
                    printf '%s  %s\n' "''${ICONS[i]}" "''${LABELS[i]}"
                  else
                    printf '%s\n' "''${LABELS[i]}"
                  fi
                done | wofi --dmenu --prompt "Audio output" || true
              )
              if [[ -z $choice ]]; then
                exit 0
              fi
              for (( i=0; i<N; i++ )); do
                entry="''${LABELS[i]}"
                if [[ -n ''${ICONS[i]} ]]; then
                  entry="''${ICONS[i]}  ''${LABELS[i]}"
                fi
                if [[ $choice == "$entry" ]]; then
                  if [[ -n ''${PROFILES[i]} && -n ''${CARDS[i]} ]]; then
                    pactl set-card-profile "''${CARDS[i]}" "''${PROFILES[i]}" || true
                    sleep 0.3
                  fi
                  pactl set-default-sink "''${SINKS[i]}" || true
                  while IFS= read -r si; do
                    if [[ -n $si ]]; then
                      pactl move-sink-input "$si" "''${SINKS[i]}" 2>/dev/null || true
                    fi
                  done < <(pactl list short sink-inputs | cut -f1)
                  pkill -RTMIN+8 waybar 2>/dev/null || true
                  break
                fi
              done
              ;;
          esac
        '';
      };
    in
    {
      imports = [ audioOutputOptions ];
      config = lib.mkIf cfg.enable {
        home.packages = [ audioOutput ];
      };
    };
}

{ ... }:
{
  flake.modules.nixos.toenail =
    { config, lib, ... }:
    let
      cfg = config.brew.toenail;
    in
    {
      options.brew.toenail = {
        enable = lib.mkEnableOption "toenail";
      };
      config = lib.mkIf cfg.enable {
        # MakeMKV drives optical hardware through the SCSI-generic /dev/sg*
        # nodes, which exist only with this module loaded.
        boot.kernelModules = [ "sg" ];
        users.users.${config.brew.user}.extraGroups = [ "cdrom" ];

        # toenail mounts the disc through udisksctl to fingerprint it for
        # TheDiscDb. Sessions reached over SSH or waypipe hold no seat, so
        # their mounts resolve to the other-seat actions, which stock polkit
        # gates behind admin authentication; granting them to a storage
        # group is the convention
        # (https://github.com/coldfix/udiskie/wiki/Permissions).
        services.udisks2.enable = true;
        users.groups.storage.members = [ config.brew.user ];
        security.polkit.extraConfig = ''
          polkit.addRule(function(action, subject) {
            var YES = polkit.Result.YES;
            var permission = {
              "org.freedesktop.udisks2.filesystem-mount": YES,
              "org.freedesktop.udisks2.filesystem-mount-other-seat": YES,
              "org.freedesktop.udisks2.eject-media": YES,
              "org.freedesktop.udisks2.eject-media-other-seat": YES
            };
            if (subject.isInGroup("storage")) {
              return permission[action.id];
            }
          });
        '';

        clan.core.vars.generators.opensubtitles_api_key = {
          share = true;
          files.opensubtitles_api_key = {
            owner = config.brew.user;
          };
          prompts.opensubtitles_api_key = {
            description = "OpenSubtitles API key";
            type = "hidden";
            persist = true;
          };
        };

        home-manager.sharedModules = [
          {
            brew.toenail = {
              enable = true;
              apiKeyFile =
                config.clan.core.vars.generators.opensubtitles_api_key.files.opensubtitles_api_key.path;
            };
          }
        ];
      };
    };

  flake.modules.homeManager.toenail =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.toenail;
    in
    {
      options.brew.toenail = {
        enable = lib.mkEnableOption "toenail";
        apiKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            File holding the OpenSubtitles API key, exported to login
            sessions as OPENSUBTITLES_API_KEY. Null leaves the variable
            unset and toenail skips subtitle verification.
          '';
        };
        settings = {
          library = lib.mkOption {
            type = lib.types.str;
            default = "/media/movies";
            description = "Directory rips are imported into.";
          };
          search = lib.mkOption {
            type = lib.types.listOf (
              lib.types.enum [
                "tmdb"
                "omdb"
                "discdb"
              ]
            );
            default = [
              "tmdb"
              "discdb"
            ];
            description = ''
              Movie databases the identification menu consults, in display
              order. tmdb and omdb read their API keys from API_KEY_TMDB and
              API_KEY_OMDB and skip themselves when unset; discdb needs no
              key.
            '';
          };
          naming = {
            movie = lib.mkOption {
              type = lib.types.str;
              default = "{name} ({year}) [{id}]";
              description = "Filename template; {id} is the rendered provider tag.";
            };
            tmdb = lib.mkOption {
              type = lib.types.str;
              default = "tmdbid-{id}";
              description = "Provider tag template for TMDb-identified movies.";
            };
            imdb = lib.mkOption {
              type = lib.types.str;
              default = "imdbid-{id}";
              description = "Provider tag template for IMDb-identified movies.";
            };
          };
          discDb = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "https://thediscdb.com";
            description = "TheDiscDb base URL, used for disc recognition, the discdb search backend, and contributions; null disables all three.";
          };
          contribute = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Offer to submit unrecognized discs' layouts to TheDiscDb after a successful rip.";
          };
          container = lib.mkOption {
            type = lib.types.enum [
              "webm"
              "mkv"
            ];
            default = "webm";
            description = ''
              Output container. webm direct-plays in browsers — jellyfin-web
              registers webm+av1+opus as a direct play profile and routes
              matroska through the HLS transcode of jellyfin-web#7546 — and
              carries only the stereo default track, since a second audio
              track in the container breaks seeking in Firefox; the original
              audio tracks ride alongside in a .mka the server offers as
              external audio, and PGS subtitles as .sup files. mkv carries
              every stream itself. Either way the subtitles used for
              verification are filed alongside as .srt once proven in sync,
              since text renders client-side while PGS forces a burn-in
              transcode.
            '';
          };
          video = {
            preset = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 4;
              description = "SVT-AV1 preset; lower is slower and better.";
            };
            crf = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 22;
              description = "SVT-AV1 constant rate factor; lower is larger and better.";
            };
            filmGrain = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 8;
              description = "SVT-AV1 film-grain synthesis level.";
            };
          };
          audio = {
            stereoKbps = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 160;
              description = "Opus bitrate of the stereo default track, in kbit/s.";
            };
            surroundKbps = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 448;
              description = "Opus bitrate of each surround track, in kbit/s.";
            };
          };
        };
      };
      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.toenail ];
        home.sessionVariables = lib.mkIf (cfg.apiKeyFile != null) {
          OPENSUBTITLES_API_KEY = "$(cat ${cfg.apiKeyFile})";
        };
        xdg.configFile."toenail/config.dhall".text =
          let
            s = cfg.settings;
            # Dhall reads "${" inside a text literal as interpolation;
            # "$" spells the dollar sign inertly.
            dhallText = v: lib.replaceStrings [ "\${" ] [ "\\u0024{" ] (builtins.toJSON v);
            backend = {
              tmdb = "Backend.Tmdb";
              omdb = "Backend.Omdb";
              discdb = "Backend.DiscDb";
            };
            # The program decodes the numeric fields as Naturals, which Dhall
            # only reads from bare literals; a sign prefix would make them
            # Integers and fail decoding.
          in
          ''
            let Backend = < DiscDb | Omdb | Tmdb >

            let Container = < Matroska | WebM >

            in  { library = ${dhallText s.library}
                , search = ${
                  if s.search == [ ] then
                    "[] : List Backend"
                  else
                    "[ ${lib.concatMapStringsSep ", " (b: backend.${b}) s.search} ]"
                }
                , naming =
                    { movie = ${dhallText s.naming.movie}
                    , tmdb = ${dhallText s.naming.tmdb}
                    , imdb = ${dhallText s.naming.imdb}
                    }
                , discDb = ${if s.discDb == null then "None Text" else "Some ${dhallText s.discDb}"}
                , contribute = ${if s.contribute then "True" else "False"}
                , container = ${if s.container == "mkv" then "Container.Matroska" else "Container.WebM"}
                , video =
                    { preset = ${toString s.video.preset}
                    , crf = ${toString s.video.crf}
                    , filmGrain = ${toString s.video.filmGrain}
                    }
                , audio =
                    { stereoKbps = ${toString s.audio.stereoKbps}
                    , surroundKbps = ${toString s.audio.surroundKbps}
                    }
                }
          '';
      };
    };
}

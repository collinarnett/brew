# brew

NixOS fleet configuration managed with [clan](https://clan.lol), built on flake-parts and import-tree.

## The Dendritic Pattern

This repo follows the dendritic pattern: modules branch like a tree from coarse profiles down to fine-grained leaves, and hosts compose by enabling profiles at the root.

The layers:

1. **Leaf modules** (`modules/*.nix`) — Each file defines a single concern (e.g., `kitty.nix`, `firefox.nix`, `ollama.nix`). Every leaf is gated by `brew.<name>.enable`. Leaves never enable other leaves directly.

2. **Profile modules** (`common.nix`, `desktop.nix`, `server.nix`, `laptop.nix`) — Profiles aggregate related leaves into a single enable flag. `brew.common.enable = true` turns on zsh, git, gpg, fzf, bat, etc. `brew.desktop.enable = true` turns on sway, waybar, kitty, firefox, pipewire, etc. `brew.server.enable = true` turns on atticd, docker-registry, restic, homelab, sops, etc. Profiles forward their enable to home-manager via `home-manager.sharedModules`.

3. **Host configurations** (`hosts/<machine>/configuration.nix`) — Each host picks its profiles and overrides individual leaf options. For example, ghoul enables `common`, `desktop`, and `laptop`; azathoth enables `common`, `desktop`, and `server`. Host-specific settings (sway outputs, keychain keys, extra packages) live here.

The key property: every module in `modules/` is auto-imported by import-tree and applied to every machine, but nothing activates until a host explicitly enables it. There is no manual import list to maintain — adding a new module file is enough.

### Mixed NixOS + Home-Manager Modules

Many modules define both `flake.modules.nixos.<name>` and `flake.modules.homeManager.<name>` in the same file. The NixOS side handles system-level config and forwards its enable flag to home-manager via `home-manager.sharedModules`. This keeps the NixOS and home-manager halves of a feature together in one file.

## Impermanence

Following the philosophy from Graham Christensen's ["Erase your darlings"](https://grahamc.com/blog/erase-your-darlings/): systems accumulate undocumented state over time — quick fixes in `/etc`, forgotten tweaks in `/var` — creating brittle, hard-to-replicate configurations. By erasing root on every boot, you invert the default: instead of preserving everything and hoping, you explicitly opt in to saving only what matters. An empty `/` is not surprising to NixOS since the system rebuilds itself from the Nix store.

Hosts running impermanence (azathoth, ghoul) roll back `zroot/root` to an empty ZFS snapshot (`zroot/root@empty`) during initrd on every boot. Everything not explicitly persisted is gone after reboot.

State that needs to survive is bind-mounted from two persistent datasets, following the [two-tier pattern](https://grahamc.com/blog/nixos-on-zfs/) of separating data by backup necessity rather than scattering it across the filesystem:

- **`/persist`** — State that must survive reboots but does not need backup (reconstructible). System logs, `/var/lib/nixos`, service state like traefik/jellyfin/authelia, NetworkManager connections. Losing this is inconvenient but recoverable.
- **`/persist/save`** — State that must both persist and be backed up (irreplaceable). User data: `~/brew`, `~/work_projects`, `~/Documents`, `~/.gnupg`, `~/.ssh`, `~/.claude`, `~/.mozilla`. This is the single dataset that restic targets for backup, keeping backups small and focused.

This split forces an explicit decision for every piece of state: is it ephemeral, reconstructible, or irreplaceable? When adding new stateful services or user directories, declare them in the host's `impermanence.nix` or they will be lost on reboot.

## Disko

Disk layout is declared per-host in `disko.nix` so that new machines can be provisioned from a single `disko` invocation — no manual partitioning. Both azathoth and ghoul use the same structure:

- Two NVMe drives in a ZFS mirror (`zroot` pool), encrypted with `aes-256-gcm` (passphrase at boot). Mirroring for redundancy, encryption because the laptops travel.
- A 500M ESP partition on the first drive for `/boot`.
- Four ZFS datasets, each with an `@empty` snapshot created at format time:
  - `root` — Ephemeral `/`. Rolled back to `@empty` on every boot.
  - `nix` — `/nix` store. Persists (rebuilding is expensive) but never backed up (fully reproducible from the flake).
  - `persist` — `/persist`. Survives reboots, not backed up.
  - `persistSave` — `/persist/save`. Survives reboots, backed up.

## Directory Layout

- `modules/` — NixOS and home-manager modules (auto-imported by import-tree). One concern per file. Directories with `default.nix` for multi-file modules (sway, waybar, wofi, etc.).
- `hosts/<machine>/` — Per-host config: `configuration.nix`, `disko.nix`, `impermanence.nix`, `facter.json`.
- `configurations/` — App-level config files referenced by modules (emacs config, claude-code skills).
- `overlays/` — Nixpkgs overlays (emacs-overlay customization, per-machine and shared overrides).
- `pkgs/` — Custom package definitions. `all-packages.nix` is the index.
- `secrets/` and `sops/` — sops-nix encrypted secrets. Never commit plaintext.
- `vars/` — clan vars (generated machine-specific values like SSH keys).

## Conventions

- Formatter is `nixfmt`. Run before committing.
- Module options live under `brew.<name>`, not directly under `services.*` or `programs.*`.
- Deploy with `clan machines update <host>`, not `nixos-rebuild`.
- Machines connect over Yggdrasil mesh VPN. Use `.clan` hostnames (e.g., `azathoth.clan`).
- azathoth is the build host for ghoul (`clan.core.networking.buildHost`).

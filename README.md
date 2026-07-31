[![NixOS
Unstable](https://img.shields.io/badge/NixOS-unstable-blue.svg?style=flat-square&logo=NixOS&logoColor=white)](https://nixos.org)

# 🧪 brew

My NixOS configuration.

## Architecture

A flake-based NixOS configuration using the dendritic pattern with
[import-tree](https://github.com/vic/import-tree) for modular
organization. All modules are automatically discovered and imported,
but each is gated by an enable option so hosts selectively activate
what they need. Secrets are managed with
[sops-nix](https://github.com/Mic92/sops-nix) and user environments
with [home-manager](https://github.com/nix-community/home-manager).

### Tooling

| Tooling       | Name          |
|---------------|---------------|
| **Editor**    | emacs         |
| **Browser**   | firefox       |
| **WM**        | sway + waybar |
| **Terminal**  | ghostty       |
| **Shell**     | zsh           |
| **Launcher**  | wofi          |
| **GTK Theme** | Dracula       |

### Hosts

#### `azathoth` 👾

My main workstation and homelab server. Runs self-hosted services
behind nginx with Kanidm single sign-on (Jellyfin, Kavita, SearX,
Grocy, rqbit, Radicle, Homepage), a Docker registry, Nix binary cache
(Atticd), and Restic backups to S3. Supports PCIe passthrough for GPU
virtualization. ZFS with impermanence for an ephemeral root
filesystem.

Specs:

| Part   | Name                                             |
|--------|--------------------------------------------------|
| CPU    | AMD Ryzen Threadripper 7960X 24-core, 48 threads |
| RAM    | Kingston Fury Renegade Pro Expo 128GB            |
| GPU    | RTX 3090 MSI SUPRIM X                            |
| GPU    | AMD Radeon PRO WX-3200                           |
| MOBO   | ASUS Pro WS TRX50-SAGE WIFI                      |
| PSU    | SeaSonic PRIME Titanium 1300W 80+ Titanium       |
| KBD    | ZSA Planck-EZ                                    |
| MOUSE  | Razer DeathAdder V2                              |
| CASE   | SilverStone Technology RM44                      |
| COOLER | SilverStone Technology XE360-TR5                 |

#### `ghoul` 👻

My portable workstation — a GPD Duo laptop with dual displays. Runs
Sway with dual waybar configurations and ZFS with impermanence for an
ephemeral root filesystem.

#### `vampire` 🧛

Development and VM host with NVIDIA GPU support, Ollama for local LLM
inference, and Docker with the NVIDIA container toolkit.

### Modules

Reusable NixOS and home-manager modules under `modules/`, selectively
enabled per host:

- **Desktop** — sway, waybar, wofi, swaylock, swayidle, greetd, GTK theming, XDG portals/MIME, mako
- **User tools** — ghostty, zsh, zoxide, starship, git, gh, fzf, bat, direnv, btop, autojump, zathura, firefox, beets
- **Services** — Ollama, Atticd, Docker registry, remote/distributed builds, Restic backups, apcupsd
- **Homelab** — nginx, Kanidm, oauth2-proxy, Jellyfin, Kavita, SearX, Grocy, rqbit, Radicle, Homepage
- **Security** — sops, GPG, keychain
- **Hardware** — PCIe passthrough, PipeWire

### Overlays

- **emacs** — Emacs Unstable with PGTK backend and custom packages
- **signal-desktop** — Dracula-themed rebuild from the [dracula org flake](https://github.com/dracula/signal-desktop)

## Motivation

NixOS lets me track and manage my Linux configuration in a declarative
centralized manner, something missing in other distros. For more
information on the advantages of Nix see the guide on [How Nix
Works](https://nixos.org/guides/how-nix-works.html).

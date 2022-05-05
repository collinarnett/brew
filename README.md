[![NixOS
Unstable](https://img.shields.io/badge/NixOS-unstable-blue.svg?style=flat-square&logo=NixOS&logoColor=white)](https://nixos.org)

# 🧪 brew

A personal NixOS configuration.

## Architecture

### Tooling

| Tooling       | Name          |
|---------------|---------------|
| **Editor**    | vim           |
| **Browser**   | firefox       |
| **WM**        | sway + waybar |
| **Terminal**  | kitty         |
| **Shell**     | zsh           |
| **Launcher**  | wofi          |
| **GTK Theme** | Dracula       |

### Hosts

#### `zombie` 🧟

My main workstation and also my server.

Specs:

| Part   | Name                                       |
|--------|--------------------------------------------|
| CPU    | AMD Ryzen 9 3900X 12-core, 24 threads      |
| RAM    | G.Skill Ripjaws V 64 GB DDR4-3200          |
| GPU    | RTX 3090 MSI SUPRIM X                      |
| GPU    | AMD Radeon PRO WX-2100                     |
| MOBO   | ASRock X470 Taichi ATX AM4                 |
| PSU    | SeaSonic PRIME Titanium 750 W 80+ Titanium |
| KBD    | ZSA Planck-EZ                              |
| MOUSE  | Razer DeathAdder V2                        |
| CASE   | Fractal Design Define R6 Blackout ATX      |
| COOLER | Noctua NH-D15                              |

## Motivation

NixOS let's me track and manage my Linux configuration in a declarative
centralized manner, something missing in other distros. For more
information on the advantages of Nix see the guide on [How Nix
Works](https://nixos.org/guides/how-nix-works.html).

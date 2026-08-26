# nixcfg

> "My home, Elaine! Where I sleep; where I come to play with my toys." -Jerry

[![CI](https://github.com/kylerisse/nixcfg/actions/workflows/ci.yml/badge.svg)](https://github.com/kylerisse/nixcfg/actions/workflows/ci.yml)
[![Images](https://github.com/kylerisse/nixcfg/actions/workflows/images.yml/badge.svg)](https://github.com/kylerisse/nixcfg/actions/workflows/images.yml)

```
nixcfg
├───network.nix: network map and lib
├───machines:
│   ├───galleta: router
│   ├───gibson: scale dev
│   ├───muir: t490 laptop
│   ├───pis: pi3 & pi4, arm dev
│   ├───qube: monitoring
│   ├───watson: workstation, gaming, ai
│   └───zugzug: macbook, nix-darwin
├───modules:
│   ├───alloy: metrics and logs push agent
│   ├───dualhome-nat: dual-wan nat (deprecated)
│   ├───grafana: service and dashboards
│   ├───he-tunnel-update: hurricane electric ipv6 tunnel endpoint updater
│   ├───kube-cluster: kubernetes
│   ├───mimir: metrics store
│   ├───mrtg: snmp network graphs
│   ├───nix-common: nix settings
│   ├───nvidia-fan-curve: gpu cooling service
│   ├───scale-signs: scale digital signage
│   ├───scale-simulator: scale simulator for dev
│   ├───ssh-server: sshd
│   ├───tempo: OTEL traces store
│   ├───users: accounts
│   └───wasgeht: network host monitor
├───pkgs:
│   ├───andiamo: nix deploy cli
│   ├───debian-netinst-iso: debian installer
│   ├───docket-unstable: issue tracker for ai and humans
│   ├───openwrt-archer-a7-v5: openwrt firmware
│   ├───openwrt-archer-c7-v2: openwrt firmware
│   ├───openwrt-one: openwrt firmware
│   ├───parrot-htb-iso: parrot os live/installer
│   ├───sdl-ss-inhibitors: cli for screensaver inhibitors
│   ├───sdl-ss-inhibitors-tray: tray app for screensaver inhibitors
│   ├───terraform: pinned terraform versions
│   ├───wasgeht: network host monitor, release
│   └───wasgeht-unstable: network host monitor, git head
├───tools:
│   └───andiamo: nix deploy cli source (go)
├───tests:
│   ├───galleta.nix: router nixos tests
│   └───monitoring.nix: monitoring stack nixos tests
└───imgs:
    ├───do.nix: digital ocean image
    ├───gnome-installer.nix: custom installer iso
    └───pi.nix: pi sd card images
```

## andiamo

andiamo is part of the devShell, so inside the repo (direnv or
`nix develop`) it is on PATH:

```
andiamo status                 # read-only fleet state
andiamo hosts                  # derived inventory + policy
andiamo deploy pi3 -dry-run    # print the action plan only
andiamo deploy -all            # gate on checks, build, push, activate
```

Example:

```
> andiamo status --no-cache
✓ galleta  evaluated  5s
✓ gibson   evaluated  6s
✓ muir     evaluated  11s
✓ pi3      evaluated  6s
✓ pi4      evaluated  6s
✓ qube     evaluated  8s
✓ watson   evaluated  15s
inventory: 0 cached, 7 evaluated in 14.9s
flake @ 5947577 (includes uncommitted changes)
   HOST     STATE        GEN  UP  KERNEL           NIXOS                                            SYSTEM
✓  galleta  in sync      27   4d  7.2.0            26.05.20260825.f4f6986                           4zmn77jg
✓  gibson   in sync      55   4d  7.2.0            digital-ocean-26.05.20260825.f4f6986             jywvr2wn
⌂  muir     local only   -    -   -                -                                                -                    no ssh server; run andiamo on the host itself
✓  pi3      in sync      51   4d  7.2.0            26.05.20260825.f4f6986                           4lfwvbml
↻  pi4      out of date  51   4d  7.2.0            26.05.20260825.f4f6986 → 26.11.20260823.56c02bc  hsis661r → 07f6k8ix
✓  qube     in sync      141  4d  7.2.0            26.05.20260825.f4f6986                           00awx6i7
↻  watson   out of date  290  8h  6.18.46 → 7.2.0  26.05.20260825.f4f6986                           35z9gjm6 → 5yxzdg7v
```

## Disk Setup

```
cryptsetup luksFormat --label=CRYPT_NIXROOT /dev/sda2
cryptsetup luksOpen /dev/disk/by-label/CRYPT_NIXROOT enc-nixroot
mkfs.ext4 -L NIXROOT /dev/mapper/enc-nixroot
```

## Collect Garbage

```
nix profile history --profile /nix/var/nix/profiles/system
sudo nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than 90d
nix-collect-garbage
```

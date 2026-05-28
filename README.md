# nixcfg

[![CI](https://github.com/kylerisse/nixcfg/actions/workflows/ci.yml/badge.svg)](https://github.com/kylerisse/nixcfg/actions/workflows/ci.yml)
[![Images](https://github.com/kylerisse/nixcfg/actions/workflows/images.yml/badge.svg)](https://github.com/kylerisse/nixcfg/actions/workflows/images.yml)

```
├───darwinConfigurations
│   └───zugzug: m2 MBP
├───checks
│   └───x86_64-linux
│       ├───galleta: derivation 'vm-test-run-galleta'
│       └───monitoring: derivation 'vm-test-run-monitoring'
├───devShells: development environment 'nix-shell'
├───formatter: package 'treefmt'
├───nixosConfigurations
│   ├───dev-router: router/dhcp/dns development
│   ├───galleta: Qotom router
│   ├───gibson: Digital Ocean VPS
│   ├───muir: T490 laptop
│   ├───pi3: Raspberry Pi3
│   ├───pi4: Raspberry Pi4
│   ├───qube: Intel NUC
│   ├───riviera: T490 laptop (DC32)
│   └───watson: Ryzen Desktop
│       ├───db: Postgres development
│       ├───k8s-master: Kubernetes master development
│       ├───k8s-worker1: Kubernetes worker development
│       └───k8s-worker2: Kubernetes worker development
└───packages
    ├───aarch64-darwin
    │   ├───docket-unstable: package 'docket-unstable'
    │   ├───terraform_1-8-2: package 'terraform_1-8-2-binary'
    │   ├───terraform_1-8-3: package 'terraform_1-8-3-binary'
    │   ├───terraform_1-9-1: package 'terraform_1-9-1-binary'
    │   └───terraform_1-9-6: package 'terraform_1-9-6-binary'
    ├───aarch64-linux
    │   ├───pi3Image: package 'nixos-sd-image'
    │   └───pi4Image: package 'nixos-sd-image'
    └───x86_64-linux
        ├───debian-netinst-iso: package 'debian-netinst-iso-12.10.0'
        ├───doImage: package 'digital-ocean-image'
        ├───docket-unstable: package 'docket-unstable'
        ├───installerISO: package 'nixos-gnome-x86_64-linux.iso'
        ├───openwrt-archer-a7-v5: package 'openwrt-archer-a7-v5-24.10.0'
        ├───openwrt-archer-c7-v2: package 'openwrt-archer-c7-v2-23.05.5'
        ├───openwrt-one: package 'openwrt-one-25.12.0'
        ├───parrot-htb-iso: package 'ParrotOS_HTB_ISO-7.1'
        ├───sdl-ss-inhibitors: package 'sdl-ss-inhibitors'
        ├───sdl-ss-inhibitors-tray: package 'sdl-ss-inhibitors-tray'
        ├───wasgeht: package 'wasgeht-0.3.0'
        └───wasgeht-unstable: package 'wasgeht-unstable'
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

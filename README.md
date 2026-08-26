# nixcfg

[![CI](https://github.com/kylerisse/nixcfg/actions/workflows/ci.yml/badge.svg)](https://github.com/kylerisse/nixcfg/actions/workflows/ci.yml)
[![Images](https://github.com/kylerisse/nixcfg/actions/workflows/images.yml/badge.svg)](https://github.com/kylerisse/nixcfg/actions/workflows/images.yml)

```
├───apps
│   ├───aarch64-darwin
│   │   └───default: app 'andiamo'
│   └───x86_64-linux
│       └───default: app 'andiamo'
├───darwinConfigurations
│   └───zugzug: m2 MBP
├───checks
│   └───x86_64-linux
│       ├───galleta: derivation 'vm-test-run-galleta'
│       └───monitoring: derivation 'vm-test-run-monitoring'
├───devShells: development environment 'nix-shell'
├───formatter: package 'treefmt'
├───nixosConfigurations
│   ├───galleta: Qotom router
│   ├───gibson: Digital Ocean VPS
│   ├───muir: T490 laptop
│   ├───pi3: Raspberry Pi3
│   ├───pi4: Raspberry Pi4
│   ├───qube: Intel NUC
│   └───watson: Ryzen Desktop
└───packages
    ├───aarch64-darwin
    │   ├───andiamo: package 'andiamo-0.1.1'
    │   ├───docket-unstable: package 'docket-unstable'
    │   ├───terraform_1-8-2: package 'terraform_1-8-2-binary'
    │   ├───terraform_1-8-3: package 'terraform_1-8-3-binary'
    │   ├───terraform_1-9-1: package 'terraform_1-9-1-binary'
    │   └───terraform_1-9-6: package 'terraform_1-9-6-binary'
    ├───aarch64-linux
    │   ├───andiamo: package 'andiamo-0.1.1'
    │   ├───pi3Image: package 'nixos-sd-image'
    │   └───pi4Image: package 'nixos-sd-image'
    └───x86_64-linux
        ├───andiamo: package 'andiamo-0.1.1'
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

## Deploy (andiamo)

`andiamo` ("let's go") lives in `tools/andiamo` and drives fleet
deployments. The host list, per-host facts, and each expected system
are derived from `nixosConfigurations` via parallel `nix eval`s,
memoized in a disposable cache keyed by tree content (`-no-cache`
bypasses; safe to delete `~/.cache/andiamo` anytime); actual state is
read from each host's system symlinks over ssh. Deploys
run in parallel; safe changes activate live with `switch`, while
boot-critical changes (kernel/initrd/kernel-modules/systemd) are staged
with `boot` and andiamo then offers to reboot the affected hosts
(`-reboot ask|auto|always|never`, default `ask`; declining or running
non-interactively leaves them `staged-awaiting-reboot` in `status`).

Per-host policy is declared right where the host is, as an inline
module in its `nixosConfigurations` entry:

```nix
qube = mkSystem {
  modules = [
    all
    ./machines/qube/configuration.nix
    { _module.args.andiamo.checks = [ "monitoring" ]; }
  ];
};
```

`checks` gates deploys to that host on flake checks; `rebootLast = true`
reboots it after all other hosts (the router). Absent attrs default.

andiamo is part of the devShell, so inside the repo (direnv or
`nix develop`) it is on PATH:

```
andiamo status                 # read-only fleet state
andiamo hosts                  # derived inventory + policy
andiamo deploy pi3 -dry-run    # print the action plan only
andiamo deploy -all            # gate on checks, build, push, activate
```

`nix run . -- <cmd>` works from anywhere (slower: re-evaluates the flake
per invocation) and the `deploy-*` Makefile targets use that form.
zugzug is not a deploy target — darwin stays on `make mac`. Cross-arch
deploys assume the operator machine builds `aarch64-linux` via binfmt,
same as `make test-all-arm-nixos`.

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

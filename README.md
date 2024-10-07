# nixcfg

```
├───darwinConfigurations
│   └───zugzug: m2 MBP
├───nixosConfigurations
│   ├───dev-router: router/dhcp/dns development
│   ├───doImage: Digital Ocean image
│   ├───installerImage: Gnome Installer ISO Image
│   ├───muir: T490 laptop
│   ├───riviera: T490 laptop (DC32)
│   └───watson: Ryzen Desktop
│       ├───db: Postgres development
│       ├───k8s-master: Kubernetes master development
│       ├───k8s-worker1: Kubernetes worker development
│       └───k8s-worker2: Kubernetes worker development
├───packages
│   ├───aarch64-darwin
│   │   ├───terraform_1-5-7: package 'terraform_1-5-7-binary'
│   │   ├───terraform_1-7-5: package 'terraform_1-7-5-binary'
│   │   ├───terraform_1-8-3: package 'terraform_1-8-3-binary'
│   │   └───terraform_1-9-1: package 'terraform_1-9-1-binary'
│   ├───aarch64-linux
│   │   ├───pi3Image: package 'nixos-sd-image'
│   │   └───pi4Image: package 'nixos-sd-image'
│   └───x86_64-linux
|       ├───debian-netinst-iso: package 'debian-netinst-iso-12.7.0'
|       ├───go-signs: package 'go-signs-2024-03-20'
|       ├───parrot-htb-iso: package 'ParrotOS_HTB_ISO-6.1'
|       ├───pi3Image: package 'nixos-sd-image'
|       └───pi4Image: package 'nixos-sd-image'
└───examples
    └───terraform-aws-bastion: example NixOS bastion on AWS
```

Disk

```
cryptsetup luksFormat --label=CRYPT_NIXROOT /dev/sda2
cryptsetup luksOpen /dev/disk/by-label/CRYPT_NIXROOT enc-nixroot
mkfs.ext4 -L NIXROOT /dev/mapper/enc-nixroot
```

Collect Garbage
```
nix profile history --profile /nix/var/nix/profiles/system
nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than 90d
nix-collect-garbage
```

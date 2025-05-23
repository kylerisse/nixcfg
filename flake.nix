{
  description = "NixOS configuration";

  inputs = {
    # linux
    nixos-2411.url = "github:nixos/nixpkgs/nixos-24.11?shallow=1";
    nixos-2505.url = "github:nixos/nixpkgs/nixos-25.05?shallow=1";
    nixos-unstable.url = "github:nixos/nixpkgs/nixos-unstable?shallow=1";
    nixos-hardware.url = "github:nixos/nixos-hardware?shallow=1";
    # mac
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.05-darwin?shallow=1";
    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.05?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    # app specific
    go-signs.url = "github:kylerisse/go-signs?ref=0.1.0";
  };

  outputs =
    inputs@{ self
    , nixos-2411
    , nixos-2505
    , nixos-unstable
    , nixos-hardware
    , nixpkgs-darwin
    , nix-darwin
    , go-signs
    }: {
      packages.aarch64-darwin =
        let
          pkgs = import nixpkgs-darwin {
            system = "aarch64-darwin";
            config.allowUnfree = true;
          };
        in
        {
          terraform_1-8-2 = pkgs.callPackage ./pkgs/terraform_1-8-2 { };
          terraform_1-8-3 = pkgs.callPackage ./pkgs/terraform_1-8-3 { };
          terraform_1-9-1 = pkgs.callPackage ./pkgs/terraform_1-9-1 { };
          terraform_1-9-6 = pkgs.callPackage ./pkgs/terraform_1-9-6 { };
        };
      packages.aarch64-linux =
        let
          pkgs = import nixos-unstable {
            system = "aarch64-linux";
          };
        in
        {
          pi3Image = (self.nixosConfigurations.piImage.extendModules {
            modules = [
              "${nixos-2505}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
              nixos-hardware.nixosModules.raspberry-pi-3
            ];
          }).config.system.build.sdImage;
          pi4Image = (self.nixosConfigurations.piImage.extendModules {
            modules = [
              "${nixos-2505}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
              nixos-hardware.nixosModules.raspberry-pi-4
            ];
          }).config.system.build.sdImage;
        };
      packages.x86_64-linux =
        let
          pkgs = import nixos-unstable {
            system = "x86_64-linux";
          };
        in
        {
          # nix build --show-trace --verbose -L .#packages.x86_64-linux.wasgeht
          debian-netinst-iso = pkgs.callPackage ./pkgs/debian-netinst-iso { };
          parrot-htb-iso = pkgs.callPackage ./pkgs/parrot-htb-iso { };
          openwrt-archer-a7-v5 = pkgs.callPackage ./pkgs/openwrt-archer-a7-v5 { };
          openwrt-archer-c7-v2 = pkgs.callPackage ./pkgs/openwrt-archer-c7-v2 { };
          openwrt-one = pkgs.callPackage ./pkgs/openwrt-one { };
          pi4Image = self.packages.aarch64-linux.pi4Image;
          pi3Image = self.packages.aarch64-linux.pi3Image;
          wasgeht = pkgs.callPackage ./pkgs/wasgeht { };
          wasgeht-unstable = pkgs.callPackage ./pkgs/wasgeht-unstable { };
        };
      darwinConfigurations =
        let
          all =
            ({ modulePath, ... }: {
              imports = [
                ./modules/nix-common
              ];
            });
        in
        {
          "zugzug" =
            let
              nixpkgs = nixpkgs-darwin;
            in
            nix-darwin.lib.darwinSystem {
              system = "aarch64-darwin";
              modules = [
                all
                ./machines/zugzug/configuration.nix
              ];
              specialArgs = { inherit inputs nixpkgs; };
            };
        };
      nixosConfigurations =
        let
          all =
            ({ modulePath, ... }: {
              imports = [
                ./modules/nix-common
                ./modules/ssh-server
                ./modules/go-signs
                ./modules/kube-cluster
                ./modules/mrtg
                ./modules/scale-simulator
                ./modules/wasgeht
              ];
            });
          users =
            ({ modulePath, ... }: {
              imports = [
                ./modules/users
              ];
            });
          kvm-guest =
            ({ modulePath, ... }: {
              imports = [
                ./modules/kvm-guest
              ];
            });
          soho-router =
            ({ modulePath, ... }: {
              imports = [
                ./modules/dualhome-nat
                ./modules/dhcp-server
                ./modules/dns-server
              ];
            });
          nixpkgs = nixos-2505;
        in
        {
          doImage = nixos-2505.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              all
              users
              ./imgs/do.nix
            ];
            specialArgs = { inherit nixpkgs; };
          };
          installerImage = nixos-2505.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              all
              ./imgs/gnome-installer.nix
            ];
            specialArgs = { inherit nixpkgs; };
          };
          piImage =
            nixos-2505.lib.nixosSystem {
              system = "aarch64-linux";
              modules = [
                all
                users
                ./imgs/pi.nix
              ];
              specialArgs = { inherit nixpkgs; };
            };
          pi3 =
            let
              hostname = "pi3";
            in
            nixos-2505.lib.nixosSystem {
              system = "aarch64-linux";
              modules = [
                all
                users
                ./machines/pis/configuration.nix
                ./machines/pis/pi3-hardware-configuration.nix
              ];
              specialArgs = { inherit nixpkgs hostname inputs; };
            };
          pi4 =
            let
              hostname = "pi4";
            in
            nixos-2505.lib.nixosSystem {
              system = "aarch64-linux";
              modules = [
                all
                users
                ./machines/pis/configuration.nix
                ./machines/pis/pi4-hardware-configuration.nix
              ];
              specialArgs = { inherit nixpkgs hostname inputs; };
            };
          dev-router = nixos-2505.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              all
              ./machines/dev-router/configuration.nix
              kvm-guest
              users
              soho-router
            ];
            specialArgs = { inherit nixpkgs self; };
          };
          gibson =
            nixos-2505.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                all
                ./machines/gibson/configuration.nix
                users
              ];
              specialArgs = { inherit nixpkgs inputs; };
            };
          watson =
            nixos-2505.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                ./machines/watson/configuration.nix
                users
                all
              ];
              specialArgs = { inherit nixpkgs inputs; };
            };
          muir = nixos-2505.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              nixos-hardware.nixosModules.lenovo-thinkpad-t490
              ./machines/muir/configuration.nix
              users
              all
            ];
            specialArgs = { inherit nixpkgs inputs; };
          };
          qube =
            let nixpkgs = nixos-2411;
            in
            nixos-2411.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                ./machines/qube/configuration.nix
                users
                all
              ];
              specialArgs = { inherit nixpkgs inputs; };
            };
          riviera = nixos-2505.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              nixos-hardware.nixosModules.lenovo-thinkpad-t490
              ./machines/riviera/configuration.nix
            ];
            specialArgs = { inherit nixpkgs; };
          };
          # watson guests
          k8s-master =
            let
              hostname = "k8s-master";
            in
            nixos-2505.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                all
                ./machines/watson/guests/kube-api-cluster.nix
                users
              ];
              specialArgs = { inherit nixpkgs hostname inputs; };
            };
          k8s-worker1 =
            let
              hostname = "k8s-worker1";
            in
            nixos-2505.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                all
                ./machines/watson/guests/kube-api-cluster.nix
                users
              ];
              specialArgs = { inherit nixpkgs hostname inputs; };
            };
          k8s-worker2 =
            let
              hostname = "k8s-worker2";
            in
            nixos-2505.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                all
                ./machines/watson/guests/kube-api-cluster.nix
                users
              ];
              specialArgs = { inherit nixpkgs hostname inputs; };
            };
          db =
            let
              hostname = "db";
            in
            nixos-2505.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                all
                ./machines/watson/guests/db.nix
                users
              ];
              specialArgs = { inherit nixpkgs hostname; };
            };
        };
    };
}

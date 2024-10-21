{
  description = "NixOS configuration";

  inputs = {
    # linux
    nixos-unstable.url = "github:nixos/nixpkgs/nixos-unstable?shallow=1";
    nixos-2405.url = "github:nixos/nixpkgs/nixos-24.05?shallow=1";
    nixos-hardware.url = "github:nixos/nixos-hardware?shallow=1";
    # mac
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs =
    inputs@{ self
    , nixos-unstable
    , nixos-2405
    , nixos-hardware
    , nixpkgs-unstable
    , nix-darwin
    }: {
      packages.aarch64-darwin =
        let
          pkgs = import nixpkgs-unstable {
            system = "aarch64-darwin";
            config.allowUnfree = true;
          };
        in
        {
          terraform_1-5-7 = pkgs.callPackage ./pkgs/terraform_1-5-7 { };
          terraform_1-7-5 = pkgs.callPackage ./pkgs/terraform_1-7-5 { };
          terraform_1-8-3 = pkgs.callPackage ./pkgs/terraform_1-8-3 { };
          terraform_1-9-1 = pkgs.callPackage ./pkgs/terraform_1-9-1 { };
        };
      packages.aarch64-linux =
        let
          pkgs = import nixos-2405 {
            system = "aarch64-linux";
          };
        in
        {
          pi3Image = (self.nixosConfigurations.piImage.extendModules {
            modules = [
              "${nixos-2405}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
              nixos-hardware.nixosModules.raspberry-pi-3
            ];
          }).config.system.build.sdImage;
          pi4Image = (self.nixosConfigurations.piImage.extendModules {
            modules = [
              "${nixos-2405}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
              nixos-hardware.nixosModules.raspberry-pi-4
            ];
          }).config.system.build.sdImage;
        };
      packages.x86_64-linux =
        let
          pkgs = import nixos-2405 {
            system = "x86_64-linux";
          };
        in
        {
          # nix build --show-trace --verbose -L .#packages.x86_64-linux.go-signs
          go-signs = pkgs.callPackage ./pkgs/go-signs { };
          debian-netinst-iso = pkgs.callPackage ./pkgs/debian-netinst-iso { };
          parrot-htb-iso = pkgs.callPackage ./pkgs/parrot-htb-iso { };
          pi4Image = self.packages.aarch64-linux.pi4Image;
          pi3Image = self.packages.aarch64-linux.pi3Image;
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
              nixpkgs = nixpkgs-unstable;
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
                ./modules/kube-cluster
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
          nixpkgs = nixos-2405;
        in
        {
          doImage = nixos-2405.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              all
              users
              ./imgs/do.nix
            ];
            specialArgs = { inherit nixpkgs; };
          };
          installerImage = nixos-2405.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              all
              ./imgs/gnome-installer.nix
            ];
            specialArgs = { inherit nixpkgs; };
          };
          piImage =
            nixos-2405.lib.nixosSystem {
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
            nixos-2405.lib.nixosSystem {
              system = "aarch64-linux";
              modules = [
                all
                users
                ./machines/pis/configuration.nix
                ./machines/pis/pi3-hardware-configuration.nix
              ];
              specialArgs = { inherit nixpkgs hostname; };
            };
          pi4 =
            let
              hostname = "pi4";
            in
            nixos-2405.lib.nixosSystem {
              system = "aarch64-linux";
              modules = [
                all
                users
                ./machines/pis/configuration.nix
                ./machines/pis/pi4-hardware-configuration.nix
              ];
              specialArgs = { inherit nixpkgs hostname; };
            };
          dev-router = nixos-2405.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./machines/dev-router/configuration.nix
              kvm-guest
              users
              soho-router
            ];
            specialArgs = { inherit nixpkgs self; };
          };
          watson =
            let
              nixpkgs = nixos-unstable;
            in
            nixos-unstable.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                ./machines/watson/configuration.nix
                users
                all
              ];
              specialArgs = { inherit nixpkgs inputs; };
            };
          muir = nixos-2405.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              nixos-hardware.nixosModules.lenovo-thinkpad-t490
              ./machines/muir/configuration.nix
              users
              all
            ];
            specialArgs = { inherit nixpkgs; };
          };
          qube = nixos-2405.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./machines/qube/configuration.nix
              users
              all
            ];
            specialArgs = { inherit nixpkgs; };
          };
          riviera = nixos-2405.lib.nixosSystem {
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
            nixos-2405.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                all
                ./machines/watson/guests/kube-api-cluster.nix
                users
              ];
              specialArgs = { inherit nixpkgs hostname; };
            };
          k8s-worker1 =
            let
              hostname = "k8s-worker1";
            in
            nixos-2405.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                all
                ./machines/watson/guests/kube-api-cluster.nix
                users
              ];
              specialArgs = { inherit nixpkgs hostname; };
            };
          k8s-worker2 =
            let
              hostname = "k8s-worker2";
            in
            nixos-2405.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                all
                ./machines/watson/guests/kube-api-cluster.nix
                users
              ];
              specialArgs = { inherit nixpkgs hostname; };
            };
          db =
            let
              hostname = "db";
            in
            nixos-2405.lib.nixosSystem {
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

{
  description = "NixOS configuration";

  inputs = {
    # linux
    nixos-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-2311.url = "github:nixos/nixpkgs/nixos-23.11";
    nixos-2405.url = "github:nixos/nixpkgs/nixos-24.05";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    # mac
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs =
    inputs@{ self
    , nixos-unstable
    , nixos-2311
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
      packages.x86_64-linux =
        let
          pkgs = import nixos-unstable {
            system = "x86_64-linux";
          };
        in
        {
          # nix build --show-trace --verbose -L .#packages.x86_64-linux.go-signs
          go-signs = pkgs.callPackage ./pkgs/go-signs { };
        };
      darwinConfigurations = {
        "zugzug" = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            ./darwin/zugzug/darwin-configuration.nix
          ];
          specialArgs = { inherit inputs; };
        };
      };
      nixosConfigurations =
        let
          common =
            ({ modulePath, ... }: {
              imports = [
                ./modules/users
                ./modules/ssh-server
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
          gamer =
            ({ modulePath, ... }: {
              imports = [
                ./modules/gamer
              ];
            });
        in
        {
          doImage = nixos-2311.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              common
              ./images/do.nix
            ];
          };
          installerImage = nixos-2405.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./images/gnome-installer.nix
            ];
          };
          dev-router = nixos-2405.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./hosts/dev-router/configuration.nix
              kvm-guest
              common
              soho-router
            ];
            specialArgs = { inherit self; };
          };
          watson = nixos-unstable.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./hosts/watson/configuration.nix
              common
            ];
            specialArgs = { inherit inputs; };
          };
          muir = nixos-unstable.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              nixos-hardware.nixosModules.lenovo-thinkpad-t490
              ./hosts/muir/configuration.nix
              common
            ];
          };
          # watson guests
          k8s-master =
            let
              hostname = "k8s-master";
            in
            nixos-2405.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                ./hosts/watson/guests/k8s-master.nix
                ./hosts/watson/guests/k8s-common.nix
                common
              ];
              specialArgs = { inherit hostname; };
            };
          k8s-worker1 =
            let
              hostname = "k8s-worker1";
            in
            nixos-2405.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                ./hosts/watson/guests/k8s-worker.nix
                ./hosts/watson/guests/k8s-common.nix
                common
              ];
              specialArgs = { inherit hostname; };
            };
          k8s-worker2 =
            let
              hostname = "k8s-worker2";
            in
            nixos-2405.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                ./hosts/watson/guests/k8s-worker.nix
                ./hosts/watson/guests/k8s-common.nix
                common
              ];
              specialArgs = { inherit hostname; };
            };
          db =
            nixos-2405.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                ./hosts/watson/guests/db.nix
                common
              ];
            };
        };
    };
}

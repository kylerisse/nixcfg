{
  description = "NixOS configuration";

  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-2311.url = "github:nixos/nixpkgs/nixos-23.11";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs =
    inputs@{ self
    , nixpkgs-unstable
    , nixpkgs-2311
    , nix-darwin
    }: {
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
          dev-router = nixpkgs-2311.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./hosts/dev-router/configuration.nix
              kvm-guest
              common
              soho-router
            ];
            specialArgs = { inherit self; };
          };
          watson = nixpkgs-unstable.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./hosts/watson/configuration.nix
              common
            ];
          };
          muir = nixpkgs-unstable.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./hosts/muir/configuration.nix
              common
            ];
          };
        };
    };
}

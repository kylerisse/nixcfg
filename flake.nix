{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
    nixinate.url = "github:matthewcroughan/nixinate";
  };

  outputs =
    { self
    , nixinate
    , nixpkgs
    , ...
    } @ inputs: {
      apps = nixinate.nixinate.x86_64-linux self;
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
              ];
            });
        in
        {
          nixos-sandbox = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./hosts/nixos-sandbox/configuration.nix
              common
            ];
          };
          dev-router = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./hosts/dev-router/configuration.nix
              kvm-guest
              common
              soho-router
            ];
          };
          area76 = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./hosts/area76/configuration.nix
              common
            ];
          };
        };
    };
}

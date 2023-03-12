{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
    nixinate.url = "github:matthewcroughan/nixinate";
  };

  outputs = {
    self,
    nixinate,
    nixpkgs,
  } @ inputs: {
    apps = nixinate.nixinate.x86_64-linux self;
    nixosConfigurations = {
      nixos-sandbox = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/nixos-sandbox/configuration.nix
        ];
      };
    };
  };
}

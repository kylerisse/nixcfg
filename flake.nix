{
  description = "NixOS configuration";

  inputs = {
    # linux
    nixos-2411.url = "github:nixos/nixpkgs/nixos-24.11?shallow=1";
    nixos-2511.url = "github:nixos/nixpkgs/nixos-25.11?shallow=1";
    nixos-unstable.url = "github:nixos/nixpkgs/nixos-unstable?shallow=1";
    nixos-master.url = "github:nixos/nixpkgs/master?shallow=1";
    nixos-hardware.url = "github:nixos/nixos-hardware?shallow=1";
    # mac
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.11-darwin?shallow=1";
    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.11?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    # app specific
    scale-signs.url = "github:socallinuxexpo/scale-signs?ref=master";
    # tools
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixos-unstable";
    };
  };

  outputs =
    inputs@{ self
    , nixos-2411
    , nixos-2511
    , nixos-unstable
    , nixos-master
    , nixos-hardware
    , nixpkgs-darwin
    , nix-darwin
    , scale-signs
    , treefmt-nix
    }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = nixos-unstable.lib.genAttrs supportedSystems;
      pkgsFor = system: import (if system == "aarch64-darwin" then nixpkgs-darwin else nixos-unstable) {
        inherit system;
      };
      mkSystem =
        { nixpkgs ? nixos-2511
        , system ? "x86_64-linux"
        , modules
        , extraSpecialArgs ? { }
        ,
        }:
        nixpkgs.lib.nixosSystem {
          inherit system modules;
          specialArgs = { inherit nixpkgs inputs; } // extraSpecialArgs;
        };
      all =
        ({ modulePath, ... }: {
          imports = [
            ./modules/nix-common
            ./modules/ssh-server
            ./modules/scale-signs
            ./modules/kube-cluster
            ./modules/mrtg
            ./modules/scale-simulator
            ./modules/wasgeht
            ./modules/users
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
      images = {
        doImage = mkSystem {
          modules = [ all ./imgs/do.nix ];
        };
        installerImage = mkSystem {
          modules = [ all ./imgs/gnome-installer.nix ];
        };
        piImage = mkSystem {
          system = "aarch64-linux";
          modules = [ all ./imgs/pi.nix ];
        };
      };
    in
    {
      devShells = forAllSystems (system:
        let pkgs = pkgsFor system;
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              gnumake
              nil
            ];
          };
        });
      formatter = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          treefmtEval = treefmt-nix.lib.evalModule pkgs {
            projectRootFile = "flake.nix";
            programs.nixpkgs-fmt.enable = true;
            programs.prettier.enable = true;
          };
        in
        treefmtEval.config.build.wrapper);
      packages.aarch64-darwin =
        let
          pkgs = import nixpkgs-darwin {
            system = "aarch64-darwin";
            config.allowUnfree = true;
          };
        in
        {
          docket-unstable = pkgs.callPackage ./pkgs/docket-unstable { };
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
          pi3Image = (images.piImage.extendModules {
            modules = [
              "${nixos-2511}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
              nixos-hardware.nixosModules.raspberry-pi-3
            ];
          }).config.system.build.sdImage;
          pi4Image = (images.piImage.extendModules {
            modules = [
              "${nixos-2511}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
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
          doImage = images.doImage.config.system.build.digitalOceanImage;
          installerISO = images.installerImage.config.system.build.isoImage;
          docket-unstable = pkgs.callPackage ./pkgs/docket-unstable { };
          wasgeht = pkgs.callPackage ./pkgs/wasgeht { };
          wasgeht-unstable = pkgs.callPackage ./pkgs/wasgeht-unstable { };
        };
      darwinConfigurations = {
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
      nixosConfigurations = {
        pi3 = mkSystem {
          system = "aarch64-linux";
          modules = [
            all
            ./machines/pis/configuration.nix
            ./machines/pis/pi3-hardware-configuration.nix
          ];
          extraSpecialArgs = { hostname = "pi3"; };
        };
        pi4 = mkSystem {
          system = "aarch64-linux";
          modules = [
            all
            ./machines/pis/configuration.nix
            ./machines/pis/pi4-hardware-configuration.nix
          ];
          extraSpecialArgs = { hostname = "pi4"; };
        };
        dev-router = mkSystem {
          modules = [
            all
            soho-router
            ./machines/dev-router/configuration.nix
          ];
          extraSpecialArgs = { inherit self; };
        };
        gibson = mkSystem {
          modules = [
            all
            ./machines/gibson/configuration.nix
          ];
        };
        watson = mkSystem {
          modules = [
            all
            ./machines/watson/configuration.nix
          ];
        };
        muir = mkSystem {
          modules = [
            all
            nixos-hardware.nixosModules.lenovo-thinkpad-t490
            ./machines/muir/configuration.nix
          ];
        };
        qube = mkSystem {
          modules = [
            all
            ./machines/qube/configuration.nix
          ];
        };
        riviera = mkSystem {
          modules = [
            nixos-hardware.nixosModules.lenovo-thinkpad-t490
            ./machines/riviera/configuration.nix
          ];
        };
        # watson guests
        k8s-master = mkSystem {
          modules = [ all ./machines/watson/guests/kube-api-cluster.nix ];
          extraSpecialArgs = { hostname = "k8s-master"; };
        };
        k8s-worker1 = mkSystem {
          modules = [ all ./machines/watson/guests/kube-api-cluster.nix ];
          extraSpecialArgs = { hostname = "k8s-worker1"; };
        };
        k8s-worker2 = mkSystem {
          modules = [ all ./machines/watson/guests/kube-api-cluster.nix ];
          extraSpecialArgs = { hostname = "k8s-worker2"; };
        };
        db = mkSystem {
          modules = [ all ./machines/watson/guests/db.nix ];
          extraSpecialArgs = { hostname = "db"; };
        };
      };
    };
}

{ config, lib, pkgs, inputs, nixpkgs, ... }:
let
  cfg = config.nix-common;
in
{
  options.nix-common = {
    enable = lib.mkEnableOption (lib.mdDoc "Baseline Nix and Nixpkgs settings");
    isDarwin = lib.mkEnableOption (lib.mdDoc "Darwin specific nix/nixpkg settings");
  };
  config = lib.mkIf cfg.enable {
    nix = {
      package = pkgs.nixVersions.latest;
      gc = {
        automatic = true;
      };
      registry = {
        nixpkgs.to = {
          type = "path";
          path = nixpkgs;
        };
      };
      settings = {
        trusted-users = if cfg.isDarwin then [ "@admin" ] else [ "@wheel" ];
        auto-optimise-store = !cfg.isDarwin; # don't optimize on Darwin, do on NixOs
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        keep-derivations = true;
        keep-outputs = true;
      };
    };
    nixpkgs.config.allowUnfree = true;
    system.stateVersion = if cfg.isDarwin then 4 else config.system.nixos.release;
  };
}

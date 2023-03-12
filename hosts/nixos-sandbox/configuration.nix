{ modulesPath, lib, pkgs, ... }:
{
  imports = lib.optional (builtins.pathExists ./do-userdata.nix) ./do-userdata.nix ++ [
    (modulesPath + "/virtualisation/digital-ocean-config.nix")
  ];

  _module.args = {
    nixinate = {
      host = "nixos-sandbox";
      sshUser = "root";
      buildOn = "remote";
    };
  };

  environment.systemPackages = with pkgs; [
    vim
    git
  ];

  system.stateVersion = "23.05";
}

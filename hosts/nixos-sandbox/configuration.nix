{ modulesPath, lib, pkgs, ... }:
{
  imports = lib.optional (builtins.pathExists ./do-userdata.nix) ./do-userdata.nix ++ [
    (modulesPath + "/virtualisation/digital-ocean-config.nix")
  ];

  _module.args = {
    nixinate = {
      host = "nixos-sandbox";
      buildOn = "remote";
      sshUser = "kylerisse";
    };
  };

  networking.hostName = "nixos-sandbox";

  environment.systemPackages = with pkgs; [
    vim
    git
  ];

  time.timeZone = "America/Los_Angeles";

  system.stateVersion = "22.11";
}

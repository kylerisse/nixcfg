{ config, pkgs, ... }:

{
  programs.steam.enable = true;
  environment.systemPackages = with pkgs; [
    steam
  ];

  users.users.gamer = {
    isNormalUser = true;
    uid = 9006;
    extraGroups = [ "networkmanager" ];
  };
}

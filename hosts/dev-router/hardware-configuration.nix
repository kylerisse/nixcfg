{ config, lib, pkgs, modulesPath, self,... }:
{
  swapDevices = [
    {
      device = "/.swapfile";
      size = (2 * 1024);
    }
  ];
}

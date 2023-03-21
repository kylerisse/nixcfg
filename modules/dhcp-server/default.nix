{ config, pkgs, inputs, lib, ... }:
{
    environment.systemPackages= with pkgs; [
        kea
    ];
    # TODO: this file assume dev-router, how to paramaterize?
    services.kea = {
        dhcp4 = {
            enable = true;
            configFile = ./kea.json;
        };
    };
}

{ config, pkgs, lib, ... }:
{
  security.pam.enableSudoTouchIdAuth = true;

  system.defaults.loginwindow = {
    GuestEnabled = false;
    DisableConsoleAccess = true;
  };

  system.defaults.finder = {
    FXEnableExtensionChangeWarning = true;
  };

  nix.settings = {
    trusted-users = [ "@admin" ];

    # https://github.com/NixOS/nix/issues/7273
    auto-optimise-store = false;

    experimental-features = [
      "nix-command"
      "flakes"
    ];

    extra-platforms = lib.mkIf (pkgs.system == "aarch64-darwin") [ "x86_64-darwin" "aarch64-darwin" ];

    keep-derivations = true;
    keep-outputs = true;
  };

  nix.configureBuildUsers = true;

  services.nix-daemon.enable = true;
  nix.package = pkgs.nix;

  environment.systemPackages = [
    pkgs.neovim
    pkgs.kitty
    pkgs.terminal-notifier
  ];
  programs.nix-index.enable = true;

  environment.shells = with pkgs; [
    bashInteractive
    fish
    zsh
  ];
  environment.variables.SHELL = "${pkgs.fish}/bin/fish";

  programs.fish.enable = true;
  programs.fish.useBabelfish = true;
  programs.fish.babelfishPackage = pkgs.babelfish;
  programs.fish.shellInit = ''
    # Nix
    if test -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
        source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
    end
    # End Nix
  '';

  system.stateVersion = 4;
}

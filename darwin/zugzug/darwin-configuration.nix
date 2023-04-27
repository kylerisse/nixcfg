{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf elem;
  caskPresent = cask: lib.any (x: x.name == cask) config.homebrew.casks;
  brewEnabled = config.homebrew.enable;
in
{
  # nix settings
  nix.settings = {
    trusted-users = [ "@admin" ];
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

  # mac settings
  # some of these require a re-login to take effect (such as dock size and 24hr time)
  system.defaults.NSGlobalDomain = {
    AppleShowAllFiles = true;
    AppleShowAllExtensions = true;
    "com.apple.trackpad.scaling" = 3.0;
    AppleInterfaceStyleSwitchesAutomatically = true;
    AppleMeasurementUnits = "Inches";
    AppleMetricUnits = 0;
    AppleShowScrollBars = "Always";
    AppleTemperatureUnit = "Fahrenheit";
    InitialKeyRepeat = 15;
    KeyRepeat = 2;
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticDashSubstitutionEnabled = false;
    NSAutomaticPeriodSubstitutionEnabled = false;
    NSDisableAutomaticTermination = true;
    NSDocumentSaveNewDocumentsToCloud = false;
    NSTableViewDefaultSizeMode = 2;
    _HIHideMenuBar = false;
    "com.apple.keyboard.fnState" = false;
    "com.apple.sound.beep.volume" = 0.4;
    "com.apple.sound.beep.feedback" = 1;
    "com.apple.swipescrolldirection" = false;
    AppleICUForce24HourTime = true;
  };

  system.defaults.dock = {
    autohide = false;
    expose-group-by-app = false;
    mru-spaces = false;
    show-recents = false;
    tilesize = 24;
    mineffect = "genie";
    minimize-to-application = false;
    orientation = "bottom";
    # Disable all hot corners
    wvous-bl-corner = 1;
    wvous-br-corner = 1;
    wvous-tl-corner = 1;
    wvous-tr-corner = 1;
  };

  system.defaults.spaces.spans-displays = false;

  system.defaults.trackpad = {
    TrackpadRightClick = true;
  };

  system.defaults.finder = {
    FXEnableExtensionChangeWarning = true;
  };

  # why is this not the default in MacOS?
  security.pam.enableSudoTouchIdAuth = true;

  # Just install everything as systemPackages rather than futz with home-manager for now
  # use chezmoi for compatibility with non NixOS / nix-darwin systems
  # some packages such as libressl and openssh already exist in OSX, but we want the latest
  environment.systemPackages = with pkgs; [
    awscli2
    bitwarden-cli
    chezmoi
    go
    htop
    icdiff
    inetutils
    jq
    kubectl
    kubectx
    libressl
    neovim
    netcat
    nixpkgs-fmt
    nmap
    rakudo
    rnix-lsp
    openssh
    python310
    python310Packages.pip
    python310Packages.boto3
    python310Packages.botocore
    silver-searcher
    terminal-notifier
    terraform_1
    terraform-docs
    terraform-lsp
    virt-manager
    yubikey-manager4
  ];
  programs.nix-index.enable = true;

  environment.shells = with pkgs; [
    bashInteractive
    fish
    zsh
  ];
  environment.variables = {
    alt_hostname = "zugzug";
  };

  # fish
  # also need to run chsh -s /run/current-system/sw/bin/fish
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

  # Use a custom configuration.nix location.
  # $ darwin-rebuild switch -I darwin-config=$HOME/.config/nixpkgs/darwin/configuration.nix
  # environment.darwinConfig = "$HOME/.config/nixpkgs/darwin/configuration.nix";

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  nix.package = pkgs.nix;

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true; # default shell on catalina

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;

  # homebrew (requires homebrew installed outside of nix)
  # /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  environment.shellInit = mkIf brewEnabled ''
    eval "$(${config.homebrew.brewPrefix}/brew shellenv)"
  '';

  # https://docs.brew.sh/Shell-Completion#configuring-completions-in-fish
  # For some reason if the Fish completions are added at the end of `fish_complete_path` they don't
  # seem to work, but they do work if added at the start.
  programs.fish.interactiveShellInit = mkIf brewEnabled ''
    if test -d (brew --prefix)"/share/fish/completions"
      set -p fish_complete_path (brew --prefix)/share/fish/completions
    end
    if test -d (brew --prefix)"/share/fish/vendor_completions.d"
      set -p fish_complete_path (brew --prefix)/share/fish/vendor_completions.d
    end
  '';

  homebrew.enable = true;
  homebrew.onActivation.autoUpdate = true;
  homebrew.onActivation.cleanup = "zap";
  homebrew.global.brewfile = true;

  homebrew.taps = [
    "homebrew/cask"
    "homebrew/cask-drivers"
    "homebrew/cask-fonts"
    "homebrew/cask-versions"
    "homebrew/core"
    "homebrew/services"
    "nrlquaker/createzap"
  ];

  # these gui apps tend to run better through homebrew
  homebrew.casks = [
    "bitwarden"
    "iterm2"
    "visual-studio-code"
  ];
}

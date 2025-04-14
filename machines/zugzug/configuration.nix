{ config, lib, pkgs, inputs, ... }:
let
  inherit (lib) mkIf elem;
  caskPresent = cask: lib.any (x: x.name == cask) config.homebrew.casks;
  brewEnabled = config.homebrew.enable;
in
{
  nix-common = {
    enable = true;
    isDarwin = true;
  };
  services.nix-daemon.enable = true;

  # mac settings
  system.startup.chime = false;

  system.defaults.NSGlobalDomain = {
    AppleShowAllFiles = true;
    AppleEnableMouseSwipeNavigateWithScrolls = false;
    AppleEnableSwipeNavigateWithScrolls = false;
    AppleShowAllExtensions = true;
    "com.apple.trackpad.scaling" = 1.0;
    "com.apple.trackpad.enableSecondaryClick" = true;
    "com.apple.trackpad.trackpadCornerClickBehavior" = 1;
    "com.apple.swipescrolldirection" = false;
    AppleInterfaceStyleSwitchesAutomatically = true;
    AppleMeasurementUnits = "Inches";
    AppleMetricUnits = 0;
    AppleShowScrollBars = "Always";
    AppleScrollerPagingBehavior = false;
    AppleTemperatureUnit = "Fahrenheit";
    InitialKeyRepeat = 15;
    KeyRepeat = 2;
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticDashSubstitutionEnabled = false;
    NSAutomaticPeriodSubstitutionEnabled = false;
    NSAutomaticQuoteSubstitutionEnabled = false;
    NSAutomaticSpellingCorrectionEnabled = false;
    NSDisableAutomaticTermination = true;
    NSAutomaticWindowAnimationsEnabled = true;
    NSDocumentSaveNewDocumentsToCloud = false;
    AppleWindowTabbingMode = "manual";
    NSNavPanelExpandedStateForSaveMode = true;
    NSNavPanelExpandedStateForSaveMode2 = true;
    PMPrintingExpandedStateForPrint = true;
    PMPrintingExpandedStateForPrint2 = true;
    NSTableViewDefaultSizeMode = 1;
    NSTextShowsControlCharacters = true;
    NSUseAnimatedFocusRing = true;
    NSScrollAnimationEnabled = true;
    NSWindowResizeTime = 0.25;
    NSWindowShouldDragOnGesture = false;
    _HIHideMenuBar = false;
    "com.apple.keyboard.fnState" = false;
    "com.apple.sound.beep.volume" = 0.2;
    "com.apple.sound.beep.feedback" = 1;
    AppleICUForce24HourTime = true;
    "com.apple.springing.enabled" = false;
    "com.apple.springing.delay" = 1.0;
  };

  # firewall set to block and stealth mode with logging
  system.defaults.alf = {
    globalstate = 2;
    loggingenabled = 1;
    stealthenabled = 1;
  };

  system.defaults.menuExtraClock = {
    IsAnalog = false;
    Show24Hour = true;
    ShowAMPM = false;
    ShowDayOfMonth = true;
    ShowDayOfWeek = true;
    ShowDate = 1;
    ShowSeconds = false;
  };

  # dock settings require re logging in
  system.defaults.dock = {
    appswitcher-all-displays = true;
    autohide = true;
    autohide-delay = 0.24;
    autohide-time-modifier = 0.8;
    dashboard-in-overlay = true;
    expose-group-apps = false;
    enable-spring-load-actions-on-all-items = true;
    expose-animation-duration = 0.8;
    launchanim = true;
    mru-spaces = false;
    tilesize = 24;
    mineffect = "genie";
    magnification = false;
    largesize = 24;
    mouse-over-hilite-stack = true;
    minimize-to-application = false;
    orientation = "bottom";
    # Disable all hot corners
    wvous-bl-corner = 1;
    wvous-br-corner = 1;
    wvous-tl-corner = 2;
    wvous-tr-corner = 1;
    persistent-apps = [
      "/System/Applications/Mission\ Control.app"
      "/Applications/Microsoft\ Teams.app"
      "/Applications/Microsoft\ Outlook.app"
      "/Applications/Google\ Chrome.app"
      "/Applications/Microsoft\ Edge.app"
      "/System/Applications/System\ Settings.app"
      "/Applications/iTerm.app"
      "/Applications/Bitwarden.app"
      "/Applications/DBeaver.app"
      "/Applications/Visual\ Studio Code.app"
      "/Applications/Cisco/Cisco\ Secure\ Client.app"
      "/Applications/Element.app"
      "/Applications/Brave Browser.app"
      "/Applications/Slack.app"
      "/System/Applications/Calculator.app"
    ];
    show-process-indicators = true;
    showhidden = true;
    show-recents = false;
    static-only = false;
  };

  system.defaults.spaces.spans-displays = false;

  system.defaults.trackpad = {
    TrackpadRightClick = true;
  };

  system.defaults.finder = {
    AppleShowAllFiles = true;
    ShowStatusBar = true;
    ShowPathbar = true;
    FXEnableExtensionChangeWarning = true;
    FXDefaultSearchScope = "SCcf";
    FXPreferredViewStyle = "clmv"; #list
    AppleShowAllExtensions = true;
    CreateDesktop = false;
    QuitMenuItem = false;
    _FXShowPosixPathInTitle = true;
  };

  system.defaults.screencapture = {
    location = "/Users/kyle.risse/Pictures/Screenshots";
    type = "png";
    disable-shadow = false;
  };

  # why is this not the default in MacOS?
  security.pam.enableSudoTouchIdAuth = true;

  # Just install everything as systemPackages rather than futz with home-manager for now
  # use chezmoi for compatibility with non NixOS / nix-darwin systems
  # some packages such as libressl and openssh already exist in OSX, but we want the latest
  environment.systemPackages = with pkgs; [
    awscli2
    brotli
    btop
    checkov
    chezmoi
    curl
    dig
    direnv
    git
    go
    gopls
    go-outline
    gotools
    icdiff
    inetutils
    jq
    k9s
    kubectl
    kubectx
    libressl
    netcat
    nixpkgs-fmt
    nodePackages.cspell
    nodePackages.jsonlint
    nodePackages_latest.markdownlint-cli
    nmap
    rakudo
    openssh
    podman
    protobuf
    pylint
    python312
    python312Packages.boto3
    python312Packages.botocore
    python312Packages.pytest
    rrdtool
    shellcheck
    silver-searcher
    terminal-notifier
    terraform_1
    inputs.self.packages.aarch64-darwin.terraform_1-8-2
    inputs.self.packages.aarch64-darwin.terraform_1-8-3
    inputs.self.packages.aarch64-darwin.terraform_1-9-1
    inputs.self.packages.aarch64-darwin.terraform_1-9-6
    terraform-docs
    terraform-lsp
    tflint
    tfsec
    vim
    wget
    yamllint
    yubikey-manager
  ];

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
    fish_add_path --prepend /run/current-system/sw/bin
    # End Nix
  '';

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true; # default shell on ventura

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
    "homebrew/services"
    "nrlquaker/createzap"
  ];

  # these gui apps tend to run better through homebrew
  homebrew.casks = [
    "1password"
    "bitwarden"
    "brave-browser"
    "dbeaver-community"
    "element"
    "flux"
    "iterm2"
    "slack"
    "visual-studio-code"
    "zoom"
  ];

  # the nixpkgs version of helm doesn't currently support aarch64-darwin
  homebrew.brews = [
    "helm"
  ];
}

# zugzug

This configuration is not integrated with the root flake. It has a few dependencies.

1. Install nix in multi-user mode `sh <(curl -L https://nixos.org/nix/install)`
1. Install brew `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
1. Apply the configuration with `darwin-switch rebuild`
1. Change shell to fish with `chsh -s /run/current-system/sw/bin/fish`
1. Use `chezmoi` to manage dotfiles

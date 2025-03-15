# zugzug

Macbook Pro leveraging `nix-darwin`.

## Dependencies

1. Install nix in multi-user mode

```
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix sh -s -- install
```

2. Install brew

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

3. Apply the configuration with `make mac`

```
darwin-rebuild switch --show-trace -vv --flake .#zugzug
```

4. Change shell to fish with

```
chsh -s /run/current-system/sw/bin/fish
```

5. Use `chezmoi` to manage dotfiles

doimage:
	nix-build images/do.nix

dodeploy:
	nix run .#apps.nixinate.nixos-sandbox

update:
	nix flake update

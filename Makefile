doimage:
	nix-build images/do.nix

deploy-nixos-sandbox:
	nix run .#apps.nixinate.nixos-sandbox

deploy-dev-router:
	nix run .#apps.nixinate.dev-router

update:
	nix flake update

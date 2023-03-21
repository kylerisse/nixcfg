doimage:
	nix-build images/do.nix

deploy-nixos-sandbox:
	nix run .#apps.nixinate.nixos-sandbox

deploy-dev-router:
	nix run .#apps.nixinate.dev-router

deploy-area76:
	nix run .#apps.nixinate.area76

update:
	nix flake update

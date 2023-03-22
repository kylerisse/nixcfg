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

lint:
	nix-shell -p nixpkgs-fmt --command 'for i in `find ./ -name "*.nix"`; do echo $$i; nixpkgs-fmt $$i; done;'

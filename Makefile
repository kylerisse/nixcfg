doimage:
	nix-build images/do.nix

deploy-dev-router:
	nix run .#apps.nixinate.dev-router

deploy-area76:
	nix run .#apps.nixinate.area76

flake-update:
	nix flake update

pin-update:
	nix registry pin github:NixOS/nixpkgs/nixos-23.05
	nix registry pin nixpkgs
	nix registry list
	nix eval nixpkgs#lib.version

lint:
	nix-shell -p nixpkgs-fmt --command 'for i in `find ./ -name "*.nix"`; do echo $$i; nixpkgs-fmt $$i; done;'

tflint:
	nix-shell -p terraform_1 --command 'for i in `find ./ -name "*.tf"`; do echo $$i; terraform fmt $$i; done;'

mac:
	darwin-rebuild switch

mac-update:
	sudo -i nix-channel --add https://github.com/nixos/nixpkgs/archive/nixos-23.05.tar.gz nixpkgs
	sudo -i nix-channel --add https://github.com/LnL7/nix-darwin/archive/master.tar.gz darwin
	sudo -i nix-channel --update

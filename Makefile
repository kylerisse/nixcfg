doImage:
	nix build -L .#nixosConfigurations.doImage.config.system.build.digitalOceanImage

deploy-dev-router:
	nixos-rebuild --flake .#dev-router --use-remote-sudo --target-host dev-router boot
	ssh dev-router.risse.tv 'sudo reboot'

lint: tflint nixlint

nixlint:
	nix-shell -p nixpkgs-fmt --command 'for i in `find ./ -name "*.nix"`; do echo $$i; nixpkgs-fmt $$i; done;'

tflint:
	NIXPKGS_ALLOW_UNFREE=1 nix-shell -p terraform_1 --command 'for i in `find ./ -name "*.tf"`; do echo $$i; terraform fmt $$i; done;'

mac:
	darwin-rebuild switch --flake .#zugzug

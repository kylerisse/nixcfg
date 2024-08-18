doImage:
	nix build -L .#nixosConfigurations.doImage.config.system.build.digitalOceanImage

installerISO:
	nix build -L .#nixosConfigurations.installerImage.config.system.build.isoImage

deploy-dev-router:
	nixos-rebuild --flake .#dev-router --use-remote-sudo --target-host dev-router boot
	ssh dev-router 'sudo reboot'

deploy-k8s-cluster:
	nixos-rebuild --flake .#k8s-master --use-remote-sudo --target-host k8s-master boot
	ssh k8s-master 'sudo reboot'
	nixos-rebuild --flake .#k8s-worker1 --use-remote-sudo --target-host k8s-worker1 boot
	ssh k8s-worker1 'sudo reboot'
	nixos-rebuild --flake .#k8s-worker2 --use-remote-sudo --target-host k8s-worker2 boot
	ssh k8s-worker2 'sudo reboot'

lint: tflint nixlint

nixlint:
	nix-shell -p nixpkgs-fmt --command 'for i in `find ./ -name "*.nix"`; do echo $$i; nixpkgs-fmt $$i; done;'

tflint:
	NIXPKGS_ALLOW_UNFREE=1 nix-shell -p terraform_1 --command 'for i in `find ./ -name "*.tf"`; do echo $$i; terraform fmt $$i; done;'

mac:
	darwin-rebuild switch --show-trace -vv --flake .#zugzug

bump-flake-darwin:
	nix flake lock --update-input nixpkgs-unstable --update-input nix-darwin

bump-flake-linux:
	nix flake lock --update-input nixos-unstable --update-input nixos-2405 --update-input nixos-hardware

doImage:
	nix build -L .#nixosConfigurations.doImage.config.system.build.digitalOceanImage

installerISO:
	nix build -L .#nixosConfigurations.installerImage.config.system.build.isoImage

deploy-dev-router:
	nixos-rebuild --flake .#dev-router --use-remote-sudo --target-host dev-router boot
	ssh dev-router 'sudo reboot'

deploy-qube-switch:
	nixos-rebuild --flake .#qube --use-remote-sudo --target-host qube switch

deploy-qube-boot:
	nixos-rebuild --flake .#qube --use-remote-sudo --target-host qube boot
	ssh qube 'sudo reboot'

deploy-k8s-cluster:
	nixos-rebuild --flake .#k8s-master --use-remote-sudo --target-host k8s-master boot
	ssh k8s-master 'sudo reboot'
	nixos-rebuild --flake .#k8s-worker1 --use-remote-sudo --target-host k8s-worker1 boot
	ssh k8s-worker1 'sudo reboot'
	nixos-rebuild --flake .#k8s-worker2 --use-remote-sudo --target-host k8s-worker2 boot
	ssh k8s-worker2 'sudo reboot'

lint: tflint nixlint

nixlint:
	nix shell nixpkgs#nixpkgs-fmt --command bash -c 'for i in `find ./ -name "*.nix"`; do echo $$i; nixpkgs-fmt $$i; done;'

tflint:
	NIXPKGS_ALLOW_UNFREE=1 nix shell --impure nixpkgs#terraform_1 --command bash -c 'for i in `find ./ -name "*.tf"`; do echo $$i; terraform fmt $$i; done;'

mac:
	darwin-rebuild switch --show-trace -vv --flake .#zugzug

bump-flake-darwin:
	nix flake update nixpkgs-unstable
	nix flake update nix-darwin

bump-flake-linux:
	nix flake update nixos-unstable
	nix flake update nixos-2405
	nix flake update nixos-hardware

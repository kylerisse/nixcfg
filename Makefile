doImage:
	nix build -vv --show-trace -L .#nixosConfigurations.doImage.config.system.build.digitalOceanImage

installerISO:
	nix build -vv --show-trace -L .#nixosConfigurations.installerImage.config.system.build.isoImage

pi3Image:
	nix build -vv --show-trace --verbose -L .#packages.aarch64-linux.pi3Image

pi4Image:
	nix build -vv --show-trace --verbose -L .#packages.aarch64-linux.pi4Image

build-pkgs:
	nix build -vv --show-trace --verbose -L .#packages.x86_64-linux.go-signs

test-all-images: installerISO doImage

test-all-nixos: lint build-pkgs
	for i in $$(echo "db dev-router k8s-master k8s-worker1 k8s-worker2 muir pi3 pi4 piImage qube riviera watson"); do echo $$i; nix build -vv --show-trace -L .#nixosConfigurations.$$i.config.system.build.toplevel; done;

test-all-local:
	bash scripts/test-all.sh

deploy-dev-router:
	nixos-rebuild --flake .#dev-router --use-remote-sudo --target-host dev-router boot
	ssh dev-router 'sudo reboot'

deploy-qube-cluster:
	nixos-rebuild --flake .#qube --use-remote-sudo --target-host qube boot
	ssh qube 'sudo reboot'
	nixos-rebuild --flake .#qube --use-remote-sudo --target-host pi3 boot
	ssh pi3 'sudo reboot'
	nixos-rebuild --flake .#qube --use-remote-sudo --target-host pi4 boot
	ssh pi4 'sudo reboot'

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

clean:
	rm -f http_cache.sqlite sbom.* vulns.csv

sbom: clean
	nix run github:tiiuae/sbomnix#sbomnix result
	nix run github:tiiuae/sbomnix#vulnxscan result

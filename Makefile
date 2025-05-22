doImage:
	nix build -vv --show-trace -L .#nixosConfigurations.doImage.config.system.build.digitalOceanImage

installerISO:
	nix build -vv --show-trace -L .#nixosConfigurations.installerImage.config.system.build.isoImage

pi3Image:
	nix build -vv --show-trace --verbose -L .#packages.aarch64-linux.pi3Image

pi4Image:
	nix build -vv --show-trace --verbose -L .#packages.aarch64-linux.pi4Image

build-pkgs:
	nix build -vv --show-trace --verbose -L .#packages.x86_64-linux.wasgeht
	nix build -vv --show-trace --verbose -L .#packages.x86_64-linux.wasgeht-unstable

test-all-images: installerISO doImage pi3Image pi4Image

test-all-nixos: lint build-pkgs
	nix build -vv --show-trace -L .#nixosConfigurations.db.config.system.build.toplevel
	nix build -vv --show-trace -L .#nixosConfigurations.dev-router.config.system.build.toplevel
	nix build -vv --show-trace -L .#nixosConfigurations.gibson.config.system.build.toplevel
	nix build -vv --show-trace -L .#nixosConfigurations.k8s-master.config.system.build.toplevel
	nix build -vv --show-trace -L .#nixosConfigurations.k8s-worker1.config.system.build.toplevel
	nix build -vv --show-trace -L .#nixosConfigurations.k8s-worker2.config.system.build.toplevel
	nix build -vv --show-trace -L .#nixosConfigurations.muir.config.system.build.toplevel
	nix build -vv --show-trace -L .#nixosConfigurations.corner.config.system.build.toplevel
	nix build -vv --show-trace -L .#nixosConfigurations.qube.config.system.build.toplevel
	nix build -vv --show-trace -L .#nixosConfigurations.pi3.config.system.build.toplevel
	nix build -vv --show-trace -L .#nixosConfigurations.pi4.config.system.build.toplevel
	nix build -vv --show-trace -L .#nixosConfigurations.riviera.config.system.build.toplevel
	nix build -vv --show-trace -L .#nixosConfigurations.watson.config.system.build.toplevel

test-all: test-all-images test-all-nixos

deploy-dev-router:
	nixos-rebuild --flake .#dev-router --use-remote-sudo --target-host dev-router boot
	ssh dev-router 'sudo reboot'

deploy-qube-cluster:
	nixos-rebuild --flake .#qube --use-remote-sudo --target-host qube boot
	ssh qube 'sudo reboot'
	nixos-rebuild --flake .#pi3 --use-remote-sudo --target-host pi3 boot
	ssh pi3 'sudo reboot'
	nixos-rebuild --flake .#pi4 --use-remote-sudo --target-host pi4 boot
	ssh pi4 'sudo reboot'

deploy-k8s-cluster:
	nixos-rebuild --flake .#k8s-master --use-remote-sudo --target-host k8s-master boot
	ssh k8s-master 'sudo reboot'
	nixos-rebuild --flake .#k8s-worker1 --use-remote-sudo --target-host k8s-worker1 boot
	ssh k8s-worker1 'sudo reboot'
	nixos-rebuild --flake .#k8s-worker2 --use-remote-sudo --target-host k8s-worker2 boot
	ssh k8s-worker2 'sudo reboot'

deploy-guests:
	nixos-rebuild --flake .#db --use-remote-sudo --target-host db boot
	ssh db 'sudo reboot'
	nixos-rebuild --flake .#corner --use-remote-sudo --target-host corner boot
	ssh corner 'sudo reboot'

deploy-gibson:
	nixos-rebuild --flake .#gibson --use-remote-sudo --target-host gibson boot
	ssh gibson 'sudo reboot'

deploy-all-nixos: deploy-guests deploy-k8s-cluster deploy-dev-router deploy-qube-cluster deploy-gibson

lint: tflint nixlint

nixlint:
	nix shell nixpkgs#nixpkgs-fmt --command bash -c 'for i in `find ./ -name "*.nix"`; do echo $$i; nixpkgs-fmt $$i; done;'

tflint:
	nix shell nixpkgs#opentofu --command bash -c 'for i in `find ./ -name "*.tf"`; do echo $$i; tofu fmt $$i; done;'

mac:
	sudo darwin-rebuild switch --show-trace -vv --flake .#zugzug

bump-flake-darwin:
	nix flake update nixpkgs-darwin
	nix flake update nix-darwin

bump-flake-linux:
	nix flake update nixos-2411
	nix flake update nixos-2505
	nix flake update nixos-unstable
	nix flake update nixos-hardware

clean:
	rm -f http_cache.sqlite sbom.* vulns.csv

sbom: clean
	nix run github:tiiuae/sbomnix#sbomnix result
	nix run github:tiiuae/sbomnix#vulnxscan result

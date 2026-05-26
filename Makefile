doImage:
	nix build -L .#packages.x86_64-linux.doImage

installerISO:
	nix build -L .#packages.x86_64-linux.installerISO

pi3Image:
	nix build -L .#packages.aarch64-linux.pi3Image

pi4Image:
	nix build -L .#packages.aarch64-linux.pi4Image

build-x86-pkgs:
	nix build -L .#packages.x86_64-linux.wasgeht
	nix build -L .#packages.x86_64-linux.wasgeht-unstable
	nix build -L .#packages.x86_64-linux.docket-unstable

test-x86-images: doImage installerISO

test-arm-images: pi3Image pi4Image

test-all-images: test-x86-images test-arm-images

test-all-arm-nixos:
	nix build -L .#nixosConfigurations.pi3.config.system.build.toplevel
	nix build -L .#nixosConfigurations.pi4.config.system.build.toplevel

test-all-x86-nixos:
	nix build -L .#nixosConfigurations.db.config.system.build.toplevel
	nix build -L .#nixosConfigurations.dev-router.config.system.build.toplevel
	nix build -L .#nixosConfigurations.galleta.config.system.build.toplevel
	nix build -L .#nixosConfigurations.gibson.config.system.build.toplevel
	nix build -L .#nixosConfigurations.k8s-master.config.system.build.toplevel
	nix build -L .#nixosConfigurations.k8s-worker1.config.system.build.toplevel
	nix build -L .#nixosConfigurations.k8s-worker2.config.system.build.toplevel
	nix build -L .#nixosConfigurations.muir.config.system.build.toplevel
	nix build -L .#nixosConfigurations.qube.config.system.build.toplevel
	nix build -L .#nixosConfigurations.riviera.config.system.build.toplevel
	nix build -L .#nixosConfigurations.watson.config.system.build.toplevel

test-all-nixos: lint check test-all-arm-nixos build-x86-pkgs test-all-x86-nixos test-galleta test-monitoring

test-all: test-all-images test-all-nixos

deploy-dev-router:
	nixos-rebuild --flake .#dev-router --sudo --target-host dev-router boot
	ssh dev-router 'sudo reboot'

deploy-qube: test-monitoring
	nixos-rebuild --flake .#qube --use-remote-sudo --target-host qube boot
	ssh qube 'sudo reboot'

deploy-pis:
	nixos-rebuild --flake .#pi3 --sudo --target-host pi3 boot
	ssh pi3 'sudo reboot'
	nixos-rebuild --flake .#pi4 --sudo --target-host pi4 boot
	ssh pi4 'sudo reboot'

deploy-k8s-cluster:
	nixos-rebuild --flake .#k8s-master --sudo --target-host k8s-master boot
	ssh k8s-master 'sudo reboot'
	nixos-rebuild --flake .#k8s-worker1 --sudo --target-host k8s-worker1 boot
	ssh k8s-worker1 'sudo reboot'
	nixos-rebuild --flake .#k8s-worker2 --sudo --target-host k8s-worker2 boot
	ssh k8s-worker2 'sudo reboot'

deploy-db:
	nixos-rebuild --flake .#db --sudo --target-host db boot
	ssh db 'sudo reboot'

deploy-gibson:
	nixos-rebuild --flake .#gibson --sudo --target-host gibson boot
	ssh gibson 'sudo reboot'

deploy-galleta: test-galleta
	nixos-rebuild --flake .#galleta --use-remote-sudo --target-host galleta boot
	ssh galleta 'sudo reboot'

deploy-all-nixos: deploy-db deploy-k8s-cluster deploy-dev-router deploy-qube deploy-pis deploy-gibson deploy-galleta

test-galleta:
	nix build -L .#checks.x86_64-linux.galleta

test-monitoring:
	nix build -L .#checks.x86_64-linux.monitoring

check:
	nix flake check

lint:
	nix fmt -- --ci

test-darwin-pkgs:
	nix build -L .#packages.aarch64-darwin.docket-unstable

mac-check:
	nix build -L .#darwinConfigurations.zugzug.config.system.build.toplevel

mac: lint check mac-check test-darwin-pkgs
	sudo darwin-rebuild switch --flake .#zugzug

bump-flake-darwin:
	nix flake update nixpkgs-darwin
	nix flake update nix-darwin

bump-flake-linux:
	nix flake update nixos-2411
	nix flake update nixos-2511
	nix flake update nixos-2605
	nix flake update nixos-master
	nix flake update nixos-unstable
	nix flake update nixos-hardware
	nix flake update treefmt-nix

clean:
	rm -i http_cache.sqlite sbom.* vulns.csv *.qcow2

sbom: clean
	nix run github:tiiuae/sbomnix#sbomnix result
	nix run github:tiiuae/sbomnix#vulnxscan result

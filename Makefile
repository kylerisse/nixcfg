doImage:
	nix build -L .#packages.x86_64-linux.doImage

installerISO:
	nix build -L .#packages.x86_64-linux.installerISO

pi3Image:
	nix build -L .#packages.aarch64-linux.pi3Image

pi4Image:
	nix build -L .#packages.aarch64-linux.pi4Image

build-x86-pkgs:
	nix build -L .#packages.x86_64-linux.andiamo
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
	nix build -L .#nixosConfigurations.galleta.config.system.build.toplevel
	nix build -L .#nixosConfigurations.gibson.config.system.build.toplevel
	nix build -L .#nixosConfigurations.muir.config.system.build.toplevel
	nix build -L .#nixosConfigurations.qube.config.system.build.toplevel
	nix build -L .#nixosConfigurations.watson.config.system.build.toplevel

test-all-nixos: lint check test-all-arm-nixos build-x86-pkgs test-all-x86-nixos

test-all: test-all-images test-all-nixos

# Boot a test's VMs into the interactive driver (Python REPL) to debug it;
# `check` is what actually runs the tests, and andiamo gates deploys on it.
debug-galleta:
	nix run .#checks.x86_64-linux.galleta.driverInteractive

debug-monitoring:
	nix run .#checks.x86_64-linux.monitoring.driverInteractive

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

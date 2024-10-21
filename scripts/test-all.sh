#!/usr/bin/bash

tasks=(
    "make lint"
    "make doImage"
    "make installerISO"
    "nix build -vv --show-trace -L .#nixosConfigurations.pi3.config.system.build.toplevel"
    "nix build -vv --show-trace -L .#nixosConfigurations.pi4.config.system.build.toplevel"
    "nix build -vv --show-trace -L .#nixosConfigurations.watson.config.system.build.toplevel"
    "nix build -vv --show-trace -L .#nixosConfigurations.muir.config.system.build.toplevel"
    "nix build -vv --show-trace -L .#nixosConfigurations.riviera.config.system.build.toplevel"
    "nix build -vv --show-trace -L .#nixosConfigurations.qube.config.system.build.toplevel"
    "nix build -vv --show-trace -L .#nixosConfigurations.k8s-master.config.system.build.toplevel"
    "nix build -vv --show-trace -L .#nixosConfigurations.k8s-worker1.config.system.build.toplevel"
    "nix build -vv --show-trace -L .#nixosConfigurations.k8s-worker2.config.system.build.toplevel"
    "nix build -vv --show-trace -L .#nixosConfigurations.db.config.system.build.toplevel"
    "nix build -vv --show-trace -L .#nixosConfigurations.dev-router.config.system.build.toplevel"
)

parallel --jobs 4 ::: "${tasks[@]}"

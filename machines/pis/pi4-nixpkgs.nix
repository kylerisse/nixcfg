{ pkgs, ... }:
{
  # https://github.com/NixOS/nixos-hardware/issues/360
  # https://discourse.nixos.org/t/does-pkgs-linuxpackages-rpi3-build-all-required-kernel-modules/42509/3
  # https://github.com/NixOS/nixpkgs/issues/126755#issuecomment-869149243
  # only necessary for pi4 but doesn't seem to harm building pi3
  nixpkgs.overlays = [
    (final: super: {
      makeModulesClosure = x:
        super.makeModulesClosure (x // { allowMissing = true; });
    })
  ];
}

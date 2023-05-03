self: super:
{
  terraform_1-3-9 = super.callPackage ./pkgs/terraform_1-3-9 { };
  terraform_1-4-2 = super.callPackage ./pkgs/terraform_1-4-2 { };
}

self: super:
{
  terraform_1-3-9 = super.callPackage ./pkgs/terraform_1-3-9 { };
  terraform_1-4-2 = super.callPackage ./pkgs/terraform_1-4-2 { };
  terraform_1-4-6 = super.callPackage ./pkgs/terraform_1-4-6 { };
  terraform_1-5-2 = super.callPackage ./pkgs/terraform_1-5-2 { };
  terraform_1-5-4 = super.callPackage ./pkgs/terraform_1-5-4 { };
  terraform_1-5-7 = super.callPackage ./pkgs/terraform_1-5-7 { };
  terraform_1-6-6 = super.callPackage ./pkgs/terraform_1-6-6 { };
}

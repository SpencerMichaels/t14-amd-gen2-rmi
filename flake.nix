{
  description = "Native RMI4 touchpad support for the Lenovo ThinkPad T14 Gen 2 AMD";

  outputs = { self }:
    let
      module = import ./nixos-module.nix { patchSource = self; };
    in
    {
      nixosModules = {
        default = module;
        tm3471-rmi = module;
      };
    };
}

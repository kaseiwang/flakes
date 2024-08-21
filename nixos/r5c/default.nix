{ config, self, nixpkgs, inputs, ... }:
{
  imports = [
    self.nixosModules.default
    ./configuration.nix
    ./hardware.nix
    ./networking.nix
    ./services.nix
    ./sdimage.nix
    self.nixosModules.chinaRoute
    inputs.sops-nix.nixosModules.sops
    {
      nixpkgs.overlays = [ self.overlays.default ];
    }
  ];
}

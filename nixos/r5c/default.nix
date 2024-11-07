{ config, self, nixpkgs, inputs, ... }:
{
  imports = [
    self.nixosModules.default
    ./configuration.nix
    ./hardware.nix
    ./networking.nix
    ./services.nix
    ./sdimage.nix
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    {
      nixpkgs.overlays = [ self.overlays.default ];
    }
  ];
}

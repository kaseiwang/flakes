{ config, self, nixpkgs, inputs, ... }:
{
  imports = [
    self.nixosModules.default
    ./configuration.nix
    ./hardware.nix
    ./networking.nix
    ./services.nix
    self.nixosModules.chinaRoute
    self.nixosModules.nievpn
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    inputs.impermanence.nixosModules.impermanence
    {
      nixpkgs.overlays = [ self.overlays.default ];
    }
  ];
}

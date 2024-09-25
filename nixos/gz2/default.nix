{ config, self, inputs, ... }:
{
  imports = [
    self.nixosModules.default
    ./configuration.nix
    ./hardware.nix
    ./networking.nix
    ./services.nix
    self.nixosModules.cloud.common
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    inputs.impermanence.nixosModules.impermanence
  ];
}

{ config, self, inputs, ... }:
{
  imports = [
    self.nixosModules.default
    ./configuration.nix
    ./hardware.nix
    ./networking.nix
    ./services.nix
    self.nixosModules.cloud.common
    #self.nixosModules.shadowsocks
    inputs.sops-nix.nixosModules.sops
    inputs.impermanence.nixosModules.impermanence
    inputs.disko.nixosModules.disko
  ];
}

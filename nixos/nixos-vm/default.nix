{ self , inputs, ... }:
{
  imports = [
    self.nixosModules.default
    self.nixosModules.shadowsocks
    self.nixosModules.cloud.common
    ./configuration.nix
    ./hardware.nix
    ./networking.nix

    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    inputs.impermanence.nixosModules.impermanence
  ];
}
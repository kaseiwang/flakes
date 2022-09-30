{ self, nixpkgs , inputs, ... }:

nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";

  modules = with self.nixosModules; [
    self.nixosModules.default
    ./configuration.nix
    ./hardware.nix
    ./networking.nix
    self.nixosModules.cloud.common
    self.nixosModules.shadowsocks
    inputs.sops-nix.nixosModules.sops
    inputs.impermanence.nixosModules.impermanence
  ];
}
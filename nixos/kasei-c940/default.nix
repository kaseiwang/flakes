{ system, self, nixpkgs, inputs }:
nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    self.nixosModules.default
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    inputs.impermanence.nixosModules.impermanence
    inputs.lanzaboote.nixosModules.lanzaboote
    ./configuration.nix
    ./hardware.nix
    ./networking.nix
    ./services.nix
    self.nixosModules.chinaRoute
    self.nixosModules.nievpn
    {
      nixpkgs.overlays = [
        self.overlays.default
      ];
    }
  ];

  specialArgs = {
    inherit inputs;
  };
}

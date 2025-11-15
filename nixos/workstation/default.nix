{
  system,
  self,
  nixpkgs,
  inputs,
}:
nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    self.nixosModules.default
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    inputs.impermanence.nixosModules.impermanence
    inputs.lanzaboote.nixosModules.lanzaboote
    ./configuration.nix
    ./hardware.nix
    ./networking.nix
    ./services.nix
    {
      nixpkgs.overlays = [
        self.overlays.default
        (_final: prev: {
          spamassassin = prev.spamassassin.overrideAttrs (_old: {
            doCheck = false;
          });
        })
      ];
    }
  ];

  specialArgs = {
    inherit inputs;
  };
}

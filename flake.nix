{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    flake-utils.url = "github:numtide/flake-utils";
    impermanence.url = "github:nix-community/impermanence";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "flake-utils";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, ... }:
  with builtins;
  with nixpkgs.lib;
  let
    this = import ./pkgs { inherit nixpkgs; };
  in
    flake-utils.lib.eachSystem [ "aarch64-linux" "x86_64-linux" ]
      (
        system:
        let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
          };
          overlays = [
            inputs.sops-nix.overlay
            this.overlay
          ];
        };
      in
      rec {
        packages = this.packages pkgs;
        legacyPackages = pkgs;
        formatter = pkgs.nixpkgs-fmt;
        devShells = with pkgs; mkShell {
          sources = attrValues self.inputs;
          nativeBuildInputs = [ colmena sops-import-keys-hook ];
        };
      }
    ) //
  {
    nixosModules = import ./modules;
    overlay = final: prev: nixpkgs.lib.composeExtensions this.overlay (import ./functions.nix) final prev;
    nixosConfigurations = {
      bwg2 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./nixos/bwg2 ];
        specialArgs = { inherit self inputs; };
      };
    };

    colmena = {
      meta = {
        specialArgs = {
          inherit self inputs;
        };
        nixpkgs = import inputs.nixpkgs {
          system = "x86_64-linux";
        };
      };
      bwg2 = { ... }: {
        deployment = {
          targetHost = "107.182.29.43";
        };
        imports = [ ./nixos/bwg2 ];
      };
    };
  };
}

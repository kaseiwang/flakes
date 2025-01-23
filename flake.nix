{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    impermanence.url = "github:nix-community/impermanence";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:kaseiwang/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, ... }:
    let
      this = import ./pkgs;
      lib = inputs.nixpkgs.lib;
    in
    flake-utils.lib.eachSystem [ "aarch64-linux" "aarch64-darwin" "x86_64-linux" ]
      (
        system:
        let
          pkgs = import nixpkgs
            {
              inherit system;
              overlays = [
                self.overlays.default
                inputs.colmena.overlay
              ];
              config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
                "rockchip-firmware-rk3568"
              ];
            } // { outPath = inputs.nixpkgs.outPath; };
        in
        {
          packages = this.packages pkgs // {
            inherit (pkgs);
          };
          legacyPackages = pkgs;
          formatter = pkgs.nixpkgs-fmt;
          devShells.default = with pkgs; mkShellNoCC {
            packages = [ colmena sops cachix e2fsprogs nvfetcher ripsecrets ];
          };
        }
      ) //
    {
      nixosModules = import ./modules;
      overlays.default = this.overlay;
      nixosConfigurations = {
        kasei-c940 = import ./nixos/kasei-c940 { system = "x86_64-linux"; inherit self inputs nixpkgs; };
      } // self.colmenaHive.nodes;

      colmenaHive = inputs.colmena.lib.makeHive ({
        meta = {
          nixpkgs = import inputs.nixpkgs {
            system = "x86_64-linux";
          };
          specialArgs = {
            inherit self inputs nixpkgs;
          };
        };
        gz2 = { ... }: {
          deployment = {
            targetHost = "gz2.kasei.im";
            buildOnTarget = false;
          };
          imports = [ ./nixos/gz2 ];
        };
        n3160 = { ... }: {
          deployment = {
            targetHost = "n3160.i.kasei.im";
            buildOnTarget = false;
          };
          imports = [ ./nixos/n3160 ];
        };
        fx63vm = { ... }: {
          deployment = {
            targetHost = "nas0.i.kasei.im";
            buildOnTarget = false;
          };
          imports = [ ./nixos/fx63vm ];
        };
        cone2 = { ... }: {
          deployment = {
            targetHost = "74.48.96.113";
            buildOnTarget = false;
          };
          imports = [ ./nixos/cone2 ];
        };
        cone3 = { ... }: {
          deployment = {
            targetHost = "66.103.210.62";
            buildOnTarget = false;
          };
          imports = [ ./nixos/cone3 ];
        };
        r5c = { ... }: {
          nixpkgs.system = "aarch64-linux";
          deployment = {
            targetHost = "ne.kasei.im";
            buildOnTarget = false;
          };
          imports = [ ./nixos/r5c ];
        };
      });
    };
}

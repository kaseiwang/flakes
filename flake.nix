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

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    let
      this = import ./pkgs;
      lib = inputs.nixpkgs.lib;
    in
    flake-utils.lib.eachSystem [ "aarch64-linux" "aarch64-darwin" "x86_64-linux" ] (
      system:
      let
        pkgs =
          import nixpkgs {
            inherit system;
            overlays = [
              self.overlays.default
              inputs.colmena.overlay
            ];
            config.allowUnfreePredicate =
              pkg:
              builtins.elem (lib.getName pkg) [
                "rockchip-firmware-rk3568"
              ];
          }
          // {
            outPath = inputs.nixpkgs.outPath;
          };
      in
      {
        packages = this.packages pkgs // {
          inherit (pkgs) ;
        };
        legacyPackages = pkgs;
        formatter = pkgs.nixfmt-tree;
        devShells.default =
          with pkgs;
          mkShellNoCC {
            packages = [
              colmena
              sops
              cachix
              e2fsprogs
              nvfetcher
              ripsecrets
            ];
          };
      }
    )
    // {
      nixosModules = import ./modules;
      overlays.default = this.overlay;
      nixosConfigurations = {
        kasei-c940 = import ./nixos/kasei-c940 {
          system = "x86_64-linux";
          inherit self inputs nixpkgs;
        };
        workstation = import ./nixos/workstation {
          system = "x86_64-linux";
          inherit self inputs nixpkgs;
        };
      }
      // self.colmenaHive.nodes;

      colmenaHive = inputs.colmena.lib.makeHive ({
        meta = {
          nixpkgs = import inputs.nixpkgs {
            system = "x86_64-linux";
          };
          specialArgs = {
            inherit self inputs nixpkgs;
          };
        };
        nas0 =
          { ... }:
          {
            deployment = {
              targetHost = "10.10.2.1";
              buildOnTarget = false;
            };
            imports = [ ./nixos/nas0 ];
          };
        cone2 =
          { ... }:
          {
            deployment = {
              targetHost = "117.55.237.3";
              buildOnTarget = false;
            };
            imports = [ ./nixos/cone2 ];
          };
        cone3 =
          { ... }:
          {
            deployment = {
              targetHost = "163.47.135.141";
              buildOnTarget = false;
            };
            imports = [ ./nixos/cone3 ];
          };
        r5c =
          { ... }:
          {
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

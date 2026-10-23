rec {
  mapPackages =
    f:
    with builtins;
    listToAttrs (
      map
        (name: {
          inherit name;
          value = f name;
        })
        (
          filter (v: v != null) (
            attrValues (mapAttrs (k: v: if v == "directory" && k != "_sources" then k else null) (readDir ./.))
          )
        )
    );
  packages = pkgs: mapPackages (name: pkgs.${name});
  overlay =
    final: prev:
    let
      sources = (import ./_sources/generated.nix) {
        inherit (final)
          fetchurl
          fetchgit
          fetchFromGitHub
          dockerTools
          ;
      };
    in
    mapPackages (
      name:
      let
        package = import ./${name};
        args = builtins.intersectAttrs (builtins.functionArgs package) { source = sources.${name}; };
      in
      final.callPackage package args
    )
    // {
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (pythonFinal: pythonPrev: {
          python-miio = pythonFinal.callPackage ./python-miio/package.nix {
            source = sources.python-miio;
          };
        })
      ];
    };
}

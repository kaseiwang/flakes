rec {
  default = (
    { ... }:
    {
      imports =
        let
          ls = dir: builtins.map (f: (dir + "/${f}")) (builtins.attrNames (builtins.readDir dir));
        in
        [ ] ++ ls ./services ++ ls ./config;
    }
  );
}

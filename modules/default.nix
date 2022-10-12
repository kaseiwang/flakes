rec {
  default = ({ ... }: {
    imports = [
      (import ./baseline.nix)
      (import ./cloud/services.nix)
    ];
  });
  shadowsocks = import ./shadowsocks;
  tinc = import ./tinc;
  cloud = {
    common = import ./cloud/common.nix;
    filesystems = import ./cloud/filesystems.nix;
  };
}

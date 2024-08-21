rec {
  default = ({ ... }: {
    imports = [
      (import ./baseline.nix)
      (import ./cloud/services.nix)
      (import ./qbittorrent.nix)
      (import ./miio-exporter.nix)
      (import ./udpxy.nix)
      (import ./sozu.nix)
      (import ./yarr.nix)
      (import ./vlmcsd.nix)
      (import ./kaseinet.nix)
      (import ./nvidia_gpu_exporter.nix)
      (import ./ddns)
    ];
  });
  cloud = {
    common = import ./cloud/common.nix;
    filesystems = import ./cloud/filesystems.nix;
  };
  chinaRoute = import ./china-route.nix;
  nievpn = import ./nievpn;
}

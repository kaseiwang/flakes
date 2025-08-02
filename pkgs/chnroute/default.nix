{ pkgs, ... }:

pkgs.stdenv.mkDerivation rec {
  pname = "chnroute";
  version = "20250430";

  src = pkgs.fetchurl {
    url = "https://ftp.apnic.net/stats/apnic/2025/delegated-apnic-${version}.gz";
    sha256 = "sha256-F0dkIoC+MfsiNEh+7SEKRhrDD9ET7USu4LtbQoza3Po=";
  };

  buildInputs = [
    pkgs.gawk
    pkgs.gzip
  ];

  dontUnpack = true;
  buildPhase = ''
    gzip -d ${src} -c | awk -F\| 'BEGIN { print "define chnv6_whitelist = {" } /CN\|ipv6/ { printf("  %s/%d,\n", $4, $5) } END { print "}" }' > chnroute-v6
    gzip -d ${src} -c | awk -F\| 'BEGIN { print "define chnv4_whitelist = {" } /CN\|ipv4/ { printf("  %s/%d,\n", $4, 32-log($5)/log(2)) } END { print "}" }' > chnroute-v4
  '';
  installPhase = ''
    mkdir $out
    mv chnroute-v{4,6} $out
  '';
}

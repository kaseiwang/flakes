{ pkgs, ... }:

pkgs.stdenv.mkDerivation rec {
  pname = "chnroute";
  version = "20241029";

  src = pkgs.fetchurl {
    url = "https://ftp.apnic.net/stats/apnic/2024/delegated-apnic-${version}.gz";
    sha256 = "sha256-I9m/jQ1xdwO3lvM5JIKiVH5XLFqferk04qIW+/MaAr0=";
  };

  buildInputs = [ pkgs.gawk pkgs.gzip ];

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

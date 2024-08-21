{ pkgs, stdenv, ... }:


stdenv.mkDerivation rec {
  pname = "wgcf_bpf_r5s";
  version = "20230223";

  platforms = [ "aarch64-linux" ];

  src = ./src;

  buildInputs = with pkgs; [ clang stdenv glibc libbpf ];

  hardeningDisable = [ "zerocallusedregs" ];

  dontUnpack = true;
  buildPhase = ''
    clang -O2 -target bpf -c ${src}/wgcf_bpf_helper.c -o wgcf_bpf -fno-stack-protector -g
  '';
  installPhase = ''
    mkdir $out
    mv wgcf_bpf $out
  '';
}

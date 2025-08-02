{ pkgs, stdenv, ... }:

stdenv.mkDerivation rec {
  pname = "wgcf_bpf";
  version = "20230223";

  src = ./src;

  buildInputs = with pkgs; [
    clang
    glibc_multi
    libbpf
  ];

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

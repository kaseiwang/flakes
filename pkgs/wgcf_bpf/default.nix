{
  pkgs,
  stdenv,
  clientId ? "0xd0, 0xec, 0x47",
  localPort ? 0,
  ...
}:

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
    clang -O2 -target bpf -D'WGCF_CLIENT_ID=${clientId}' -DWGCF_LOCAL_PORT=${toString localPort} -c ${src}/wgcf_bpf_helper.c -o wgcf_bpf -fno-stack-protector -g
  '';
  installPhase = ''
    mkdir $out
    mv wgcf_bpf $out
  '';
}

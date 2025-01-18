{ source
, lib
, pkgs
, stdenv
, fetchFromGitHub
, buildGoModule
}:

buildGoModule rec {
  inherit (source) pname version src;

  vendorHash = "sha256-ZzZ7MJUxXL+rX7SAHHT+KMHDkCDi5qTeAIkg4bAtMio=";

  meta = with lib; {
    description = "Nvidia GPU exporter for prometheus using nvidia-smi binary";
    homepage = "https://github.com/utkuozdemir/nvidia_gpu_exporter";
    license = licenses.mit;
  };
}

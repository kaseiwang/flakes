{ source
, lib
, pkgs
, stdenv
, fetchFromGitHub
, buildGoModule
}:

buildGoModule rec {
  inherit (source) pname version src;

  vendorHash = "sha256-ev7k4dSu0ymg2Tn28oTVgEDSyUpaK0POg91ikC9G7Gs=";

  meta = with lib; {
    description = "Nvidia GPU exporter for prometheus using nvidia-smi binary";
    homepage = "https://github.com/utkuozdemir/nvidia_gpu_exporter";
    license = licenses.mit;
  };
}

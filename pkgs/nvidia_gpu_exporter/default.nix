{ source
, lib
, pkgs
, stdenv
, fetchFromGitHub
, buildGoModule
}:

buildGoModule rec {
  inherit (source) pname version src;

  vendorHash = "sha256-Dsp98EWRiRaawYmdr3KR2YTteeD9cmHUHQoq5CnH9gA=";

  meta = with lib; {
    description = "Nvidia GPU exporter for prometheus using nvidia-smi binary";
    homepage = "https://github.com/utkuozdemir/nvidia_gpu_exporter";
    license = licenses.mit;
  };
}

{
  source,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkgs,
  lib,
}:

rustPlatform.buildRustPackage rec {
  inherit (source) pname version src;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = with pkgs; [
    pkg-config
    perl
    makeWrapper
    rustPlatform.cargoSetupHook
    cargo
    rustc
  ];

  buildInputs = with pkgs; [ openssl ];

  doCheck = true;

  meta = with lib; {
    description = "All-in-one proxy written in Rust.";
    homepage = "https://rabbit-digger.com/";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "rabbit-digger-pro";
  };
}

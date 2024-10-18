{ source, stdenv, pkgs, lib, pnpm_9, fetchFromGitHub, buildNpmPackage }:

let
  author = "Xhofe <i@nn.ci>";
in
pkgs.stdenv.mkDerivation (finalAttrs: {
  inherit (source) pname version src;

  pnpmDeps = pnpm_9.fetchDeps {
    inherit (finalAttrs) pname version src;
    hash = "sha256-w8nK4TKukSGsCSaujK+Ck+wb0nGxJ6+S1lzdZOmq2uY=";
  };

  nativeBuildInputs = with pkgs; [
    nodejs
    pnpm_9.configHook
  ];

  buildPhase = ''
    runHook preBuild

    pnpm i18n:release
    pnpm build

    runHook postBuild
  '';


  installPhase = ''
    runHook preInstall

    mkdir $out
    mv dist $out

    runHook postInstall
  '';

  meta = with lib; {
    description = "A file list/WebDAV program that supports multiple storages, powered by Gin and Solidjs.";
    homepage = "https://alist.nn.ci";
    license = licenses.agpl3Only;
  };
})

{ source, stdenv, pkgs, lib, fetchFromGitHub, buildGoModule }:

let
  author = "Xhofe <i@nn.ci>";
in
buildGoModule {
  inherit (source) pname version src;

  buildInputs = with pkgs; [ fuse ];

  vendorHash = "sha256-qSbvb2/y5rdS/OCutNEcRDUQBCAgNudux8XDnY9TRSo=";

  tags = [ "jsoniter" ];

  ldflags = [
    "-w"
    "-s"
    #"-X github.com/alist-org/alist/v3/internal/conf.BuiltAt=${}"
    "-X 'github.com/alist-org/alist/v3/internal/conf.GoVersion=${lib.getVersion pkgs.go}'"
    "-X 'github.com/alist-org/alist/v3/internal/conf.GitAuthor=${author}'"
    #"-X github.com/alist-org/alist/v3/internal/conf.GitCommit=${}"
    "-X 'github.com/alist-org/alist/v3/internal/conf.Version=${source.version}'"
    "-X 'github.com/alist-org/alist/v3/internal/conf.WebVersion=${pkgs.alist-web.version}'"
  ];

  preBuild = ''
    rm -rf public/dist
    cp -rp ${pkgs.alist-web}/dist public
  '';

  doCheck = false;

  meta = with lib; {
    description = "A file list/WebDAV program that supports multiple storages, powered by Gin and Solidjs.";
    homepage = "https://alist.nn.ci";
    license = licenses.agpl3Only;
  };
}

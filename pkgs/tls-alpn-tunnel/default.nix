{ pkgs, buildGoModule, ... }:


buildGoModule {
  pname = "tls-alpn-tunnel";
  version = "20221020";

  src = ./src;
  vendorHash = "sha256-35FFB//rMXkNoWWTlbvTC8aoEWOlHJnJJACmiQbh7Co=";
}

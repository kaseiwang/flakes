{ config, pkgs, ... }:
{
  services.nginx = {
    enable = true;
    streamConfig = ''
      server {
        listen 0.0.0.0:9555 reuseport;
        proxy_timeout 1800s;
        proxy_pass 10.10.2.1:9555;
      }
    '';
  };
}

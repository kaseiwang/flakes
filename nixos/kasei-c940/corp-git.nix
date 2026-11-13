{ config, lib, ... }:
{
  # Keep identity, hostnames and URL rewrites out of the Nix store and Git history.
  # The SSH fragment is used only by the conditionally included Git configuration.
  sops.secrets = {
    c940-corp-git-config = {
      owner = "kasei";
      mode = "0400";
    };
    c940-corp-ssh-config = {
      owner = "kasei";
      mode = "0400";
    };
  };

  home-manager.users.kasei.programs.git.includes = lib.mkAfter [
    {
      condition = "gitdir:~/corp/";
      path = config.sops.secrets.c940-corp-git-config.path;
    }
  ];
}

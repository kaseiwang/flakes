{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/var/lib/comfyui";
  # Use the same numeric UID inside and outside the container; no host home or Docker socket
  # is exposed to ComfyUI. Group access lets kasei manage inputs and outputs.
  uid = 10001;
  gid = 10001;
  imageContext = pkgs.runCommand "comfyui-image-context" { } ''
    mkdir -p "$out"
    cp ${./comfyui/Dockerfile} "$out/Dockerfile"
    cp ${./comfyui/requirements.lock} "$out/requirements.lock"
    cp ${./comfyui/h3-compatibility.patch} "$out/h3-compatibility.patch"
  '';
  imageKey = builtins.substring 0 32 (
    builtins.hashString "sha256" (
      builtins.readFile ./comfyui/Dockerfile
      + builtins.readFile ./comfyui/requirements.lock
      + builtins.readFile ./comfyui/h3-compatibility.patch
    )
  );
  image = "localhost/comfyui-h3:${imageKey}";
  proxyEnvironment = config.networking.proxy.envVars;

  prepare = pkgs.writeShellApplication {
    name = "comfyui-prepare";
    runtimeInputs = [
      pkgs.btrfs-progs
      pkgs.coreutils
    ];
    text = ''
      install -d -m 0750 -o root -g comfyui ${dataDir}
      # Nested subvolumes are excluded from the existing nixos_persist snapshots.
      # Refuse to silently convert an existing directory or relocate its contents.
      for name in models cache; do
        path=${dataDir}/"$name"
        if [[ ! -e "$path" ]]; then
          btrfs subvolume create "$path"
        fi
        btrfs subvolume show "$path" >/dev/null
        chown comfyui:comfyui "$path"
        chmod 2770 "$path"
      done
      for name in input output user user/default user/default/workflows; do
        install -d -m 2770 -o comfyui -g comfyui ${dataDir}/"$name"
      done
      install -d -m 2770 -o comfyui -g comfyui ${dataDir}/cache/tmp
      # A separate supplied workflow leaves user-saved workflows untouched.
      install -m 0660 -o comfyui -g comfyui \
        ${./comfyui/workflow.json} ${dataDir}/user/default/workflows/minimax-h3-q4-starter.json
    '';
  };
  buildImage = pkgs.writeShellApplication {
    name = "comfyui-build-image";
    runtimeInputs = [ pkgs.docker ];
    text = ''
      if ! docker image inspect ${lib.escapeShellArg image} >/dev/null 2>&1; then
        docker build --pull=false --network=host \
          --build-arg HTTP_PROXY --build-arg HTTPS_PROXY --build-arg NO_PROXY \
          --build-arg http_proxy --build-arg https_proxy --build-arg no_proxy \
          --tag ${lib.escapeShellArg image} ${imageContext}
      fi
    '';
  };
in
{
  hardware.nvidia-container-toolkit.enable = true;

  users.groups.comfyui.gid = gid;
  users.users.comfyui = {
    isSystemUser = true;
    inherit uid;
    group = "comfyui";
    home = dataDir;
  };
  users.users.kasei.extraGroups = [ "comfyui" ];

  # None of these services is wanted by a boot target. Switching the flake does
  # not download weights, build the image or start an idle GPU consumer.
  systemd.services.comfyui-prepare = {
    description = "Prepare persistent ComfyUI directories";
    unitConfig.RequiresMountsFor = [ dataDir ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe prepare;
      UMask = "0007";
    };
  };

  systemd.services.comfyui-image = {
    description = "Build the pinned ComfyUI CUDA image on demand";
    requires = [ "docker.service" ];
    after = [
      "docker.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    environment = proxyEnvironment;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe buildImage;
      TimeoutStartSec = "infinity";
    };
  };

  systemd.services."comfyui-models@" = {
    description = "Download and verify ComfyUI model set %i";
    requires = [ "comfyui-prepare.service" ];
    after = [
      "comfyui-prepare.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    environment = proxyEnvironment // {
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };
    path = [ pkgs.curl ];
    serviceConfig = {
      Type = "oneshot";
      User = "comfyui";
      Group = "comfyui";
      UMask = "0007";
      ExecStart = "${lib.getExe pkgs.python3} ${./comfyui/download-models.py} ${./comfyui/models.json} ${dataDir}/models %i";
      TimeoutStartSec = "infinity";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ "${dataDir}/models" ];
    };
  };

  virtualisation.oci-containers = {
    backend = "docker";
    containers.comfyui = {
      inherit image;
      autoStart = false;
      pull = "never";
      user = "${toString uid}:${toString gid}";
      ports = [ "127.0.0.1:8188:8188" ];
      devices = [ "nvidia.com/gpu=0" ];
      volumes = [ "${dataDir}:/data" ];
      capabilities.ALL = false;
      extraOptions = [
        "--security-opt=no-new-privileges:true"
        "--shm-size=1g"
      ];
      cmd = [
        "--listen"
        "0.0.0.0"
        "--port"
        "8188"
        "--models-directory"
        "/data/models"
        "--input-directory"
        "/data/input"
        "--output-directory"
        "/data/output"
        "--user-directory"
        "/data/user"
        "--temp-directory"
        "/data/cache/tmp"
        "--database-url"
        "sqlite:////data/user/comfyui.db"
        # GGUF uses its own ModelPatcher. Begin with explicit CPU offload;
        # lowvram also places the large Qwen text encoder on CPU (slower).
        "--disable-dynamic-vram"
        "--lowvram"
        "--reserve-vram"
        "3"
        "--cache-ram"
        "6"
        "--disable-api-nodes"
      ];
    };
  };

  systemd.services.docker-comfyui = {
    requires = [
      "docker.service"
      "comfyui-prepare.service"
      "comfyui-image.service"
      "nvidia-container-toolkit-cdi-generator.service"
    ];
    after = [
      "comfyui-prepare.service"
      "comfyui-image.service"
      "nvidia-container-toolkit-cdi-generator.service"
    ];
    serviceConfig.RestartSec = "10s";
  };
}

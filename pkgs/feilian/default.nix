{
  pkgs,
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
}:
let
  # Based on zrubing/nix-config at e569287771599850b2759cec404125e0439b447a.
  version = "3.2.16";
  unpacked = stdenvNoCC.mkDerivation {
    pname = "feilian-unpacked";
    inherit version;
    src = fetchurl {
      name = "feilian-${version}.deb";
      url = "https://cdn.isealsuite.com/linux/FeiLian_Linux_amd64_v${version}_r7356_adbfd9.%7Bbytedance%7D.deb";
      hash = "sha256-QLGLkgLUq4Z7ljt6mVVAyJuyqONjjqpQ8rtWddbdM2w=";
    };
    nativeBuildInputs = [ dpkg ];
    dontUnpack = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      dpkg-deb -x $src $out
      find $out -type f -name 'corplink*' -exec chmod +x {} \;
      runHook postInstall
    '';
  };
  fhsEnv = pkgs.buildFHSEnv {
    name = "feilian-fhs";
    multiPkgs =
      pkgs: with pkgs; [
        mesa
        libgbm
        libglvnd
        libdrm
        glibc
        gcc.cc.lib
      ];
    targetPkgs =
      pkgs: with pkgs; [
        gtk3
        glib
        nss
        nspr
        libx11
        libxcb
        libxcomposite
        libxcursor
        libxdamage
        libxext
        libxfixes
        libxi
        libxrender
        libxtst
        libxrandr
        libxscrnsaver
        alsa-lib
        dbus
        at-spi2-core
        pango
        cairo
        cups
        expat
        gdk-pixbuf
        libnotify
        libappindicator-gtk3
        libsecret
        systemd
        libxkbcommon
        curl
        iproute2
        iptables
        kmod
        dnsmasq
        procps
        nettools
        networkmanager
        which
      ];
    extraBuildCommands = ''
      mkdir -p $out/feilian-libs
      # Keep these libraries available independently of /usr/lib mounts.
      ln -s ${lib.getLib pkgs.libgbm}/lib/libgbm.so.1 $out/feilian-libs/libgbm.so.1
      ln -s ${lib.getLib pkgs.libdrm}/lib/libdrm.so.2 $out/feilian-libs/libdrm.so.2
      ln -s ${lib.getLib pkgs.systemd}/lib/libudev.so.1 $out/feilian-libs/libudev.so.1
    '';
    extraBwrapArgs = [
      "--ro-bind ${unpacked}/opt /opt"
      "--bind /var/lib/feilian /opt/apps/com.volcengine.feilian/files"
      "--bind /etc/NetworkManager /etc/NetworkManager"
    ];
    profile = ''
      export NODE_ENV=production
      export LD_LIBRARY_PATH=/feilian-libs:/usr/lib:/usr/lib64:/lib:/lib64:''${LD_LIBRARY_PATH:-}
      export XDG_DATA_DIRS=${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}:''${XDG_DATA_DIRS:-}
    '';
    runScript = "bash";
  };
  client = pkgs.writeShellScriptBin "feilian" ''
    exec ${fhsEnv}/bin/feilian-fhs -c 'exec /opt/apps/com.volcengine.feilian/files/corplink --no-sandbox "$@"' -- "$@"
  '';
  service = pkgs.writeShellScriptBin "feilian-service" ''
    exec ${fhsEnv}/bin/feilian-fhs -c 'exec /opt/apps/com.volcengine.feilian/files/corplink-service "$@"' -- "$@"
  '';
  desktopItem = pkgs.makeDesktopItem {
    name = "feilian";
    desktopName = "FeiLian";
    genericName = "飞连客户端";
    exec = "${client}/bin/feilian";
    icon = "corplink";
    categories = [ "Network" ];
  };
in
pkgs.symlinkJoin {
  name = "feilian-${version}";
  pname = "feilian";
  inherit version;
  passthru = { inherit unpacked fhsEnv; };
  paths = [
    client
    service
    desktopItem
  ];
  postBuild = ''
    install -Dm644 ${unpacked}/opt/apps/com.volcengine.feilian/entries/icons/hicolor/256x256/apps/corplink.png \
      $out/share/icons/hicolor/256x256/apps/corplink.png
  '';
  meta = {
    description = "飞连客户端";
    homepage = "https://www.volcengine.com/product/feilian";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "feilian";
  };
}

# This file was generated by nvfetcher, please do not modify it manually.
{ fetchgit, fetchurl, fetchFromGitHub, dockerTools }:
{
  aws-lc = {
    pname = "aws-lc";
    version = "v1.40.0";
    src = fetchFromGitHub {
      owner = "aws";
      repo = "aws-lc";
      rev = "v1.40.0";
      fetchSubmodules = false;
      sha256 = "sha256-EozdMEI13Z0uDncBnO25tu0FnkDu4afxuMambtO9af8=";
    };
  };
  fcitx5-pinyin-zhwiki = {
    pname = "fcitx5-pinyin-zhwiki";
    version = "20240909";
    src = fetchurl {
      url = "https://github.com/felixonmars/fcitx5-pinyin-zhwiki/releases/download/0.2.5/zhwiki-20240909.dict";
      sha256 = "sha256-djXrwl1MmiAf0U5Xvm4S7Fk2fKNRm5jtc94KUYIrcm8=";
    };
  };
  nvidia_gpu_exporter = {
    pname = "nvidia_gpu_exporter";
    version = "v1.2.1";
    src = fetchFromGitHub {
      owner = "utkuozdemir";
      repo = "nvidia_gpu_exporter";
      rev = "v1.2.1";
      fetchSubmodules = false;
      sha256 = "sha256-+YmZ25OhOeIulkOH/Apqh3jGQ4Vanv0GIuc/EjBiZ+w=";
    };
  };
  qbittorrent-enhanced-nox = {
    pname = "qbittorrent-enhanced-nox";
    version = "release-5.0.2.10";
    src = fetchFromGitHub {
      owner = "c0re100";
      repo = "qBittorrent-Enhanced-Edition";
      rev = "release-5.0.2.10";
      fetchSubmodules = false;
      sha256 = "sha256-9RCG530zWQ+qzP0Y+y69NFlBWVA8GT29dY8aC1cvq7o=";
    };
  };
  rabbit-digger-pro = {
    pname = "rabbit-digger-pro";
    version = "d6630cbcdc0c5866b12b0eb3411949e55b8997cd";
    src = fetchgit {
      url = "https://github.com/rabbit-digger/rabbit-digger-pro";
      rev = "d6630cbcdc0c5866b12b0eb3411949e55b8997cd";
      fetchSubmodules = true;
      deepClone = false;
      leaveDotGit = false;
      sha256 = "sha256-zYSnJd35EsLjXW1Yvg5FakT/QMkKHOd6+SwKLxuY3BY=";
    };
    "Cargo.lock" = builtins.readFile ./rabbit-digger-pro-d6630cbcdc0c5866b12b0eb3411949e55b8997cd/Cargo.lock;
    date = "2024-11-19";
  };
  smartdns-china-list = {
    pname = "smartdns-china-list";
    version = "35d765943e6c6771afac8216ada30a7a1676f64b";
    src = fetchFromGitHub {
      owner = "felixonmars";
      repo = "dnsmasq-china-list";
      rev = "35d765943e6c6771afac8216ada30a7a1676f64b";
      fetchSubmodules = false;
      sha256 = "sha256-oUUNmfl68Ajn0vZgvF8SH6O/M0INtWGmadCu5Mur/ok=";
    };
    date = "2024-12-04";
  };
  vscode-ext-ccls = {
    pname = "vscode-ext-ccls";
    version = "0.1.29";
    src = fetchurl {
      url = "https://ccls-project.gallery.vsassets.io/_apis/public/gallery/publisher/ccls-project/extension/ccls/0.1.29/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage";
      name = "ccls-0.1.29.zip";
      sha256 = "sha256-RjMYBLgbi+lgPqaqN7yh8Q8zr9euvQ+YLEoQaV3RDOA=";
    };
    publisher = "ccls-project";
    name = "ccls";
  };
  vscode-ext-codeium = {
    pname = "vscode-ext-codeium";
    version = "1.29.8";
    src = fetchurl {
      url = "https://Codeium.gallery.vsassets.io/_apis/public/gallery/publisher/Codeium/extension/codeium/1.29.8/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage";
      name = "codeium-1.29.8.zip";
      sha256 = "sha256-/+PGEjnGH+ssPjz3zS6eUfPku0/o9Xz2TR4q1TBnFWA=";
    };
    publisher = "Codeium";
    name = "codeium";
  };
  vscode-ext-sops = {
    pname = "vscode-ext-sops";
    version = "0.9.1";
    src = fetchurl {
      url = "https://signageos.gallery.vsassets.io/_apis/public/gallery/publisher/signageos/extension/signageos-vscode-sops/0.9.1/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage";
      name = "signageos-vscode-sops-0.9.1.zip";
      sha256 = "sha256-b1Gp+tL5/e97xMuqkz4EvN0PxI7cJOObusEkcp+qKfM=";
    };
    publisher = "signageos";
    name = "signageos-vscode-sops";
  };
  xdg-open-server = {
    pname = "xdg-open-server";
    version = "v1.3";
    src = fetchFromGitHub {
      owner = "kitsunyan";
      repo = "xdg-open-server";
      rev = "v1.3";
      fetchSubmodules = false;
      sha256 = "sha256-BX/Z3e1MQMISWWtrw+D1ChwdIhwxgWOx2evgZdMkPjg=";
    };
  };
  yarr-pgsql = {
    pname = "yarr-pgsql";
    version = "v3.1.3";
    src = fetchFromGitHub {
      owner = "jgkawell";
      repo = "yarr";
      rev = "v3.1.3";
      fetchSubmodules = false;
      sha256 = "sha256-9tQFUlKy3alaAiZDjhtfoVY1rvISD8aRlyODc2gs5e8=";
    };
  };
}

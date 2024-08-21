{ pkgs, ... }:
pkgs.stdenv.mkDerivation rec {
  pname = "fcitx5-pinyin-custom-pinyin-dictionary";
  version = "20240621";

  src = pkgs.fetchurl {
    url = "https://github.com/wuhgit/CustomPinyinDictionary/releases/download/assets/CustomPinyinDictionary_Fcitx_${version}.tar.gz";
    sha256 = "sha256-IAdJ19XsjFTcPej8DFwFT7RgJ3HvyXEcLMGgjB+lOIQ=";
  };

  unpackPhase = ''
    runHook preUnpack

    tar -xf $src

    runHook postUnpack
  '';
  installPhase = ''
    install -Dm644 $src $out/share/fcitx5/pinyin/dictionaries/CustomPinyinDictionary_Fcitx.dict
  '';
  meta = with pkgs.lib; {
    description = "Fcitx5 自建拼音输入法词库，百万常用词汇量。";
    homepage = "https://github.com/wuhgit/CustomPinyinDictionary";
    license = licenses.unlicense;
  };
}

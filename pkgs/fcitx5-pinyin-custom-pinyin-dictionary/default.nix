{ pkgs, ... }:
pkgs.stdenv.mkDerivation rec {
  pname = "fcitx5-pinyin-custom-pinyin-dictionary";
  version = "20260101";

  src = pkgs.fetchurl {
    url = "https://github.com/wuhgit/CustomPinyinDictionary/releases/download/assets/CustomPinyinDictionary_Fcitx.dict";
    sha256 = "sha256-Y2d7DhvNknbo7u9BVTq1Mr9gYSeFWNnvo2KbDr6INuU=";
  };

  phases = [ "buildPhase" "installPhase" "fixupPhase" ];

  installPhase = ''
    install -Dm644 $src $out/share/fcitx5/pinyin/dictionaries/CustomPinyinDictionary_Fcitx.dict
  '';
  meta = with pkgs.lib; {
    description = "Fcitx5 自建拼音输入法词库，百万常用词汇量。";
    homepage = "https://github.com/wuhgit/CustomPinyinDictionary";
    license = licenses.unlicense;
  };
}

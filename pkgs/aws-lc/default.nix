{ source
, lib
, pkgs
, stdenv
, fetchFromGitHub
, cmake
, ninja
, perl
, buildGoModule
}:

buildGoModule {
  inherit (source) pname version src;

  nativeBuildInputs = with pkgs; [
    cmake
    ninja
    perl
  ];

  vendorHash = "sha256-hHWsEXOOxJttX+k0gy/QXvR+yhQLBjE40QIOpwCNpFU=";
  proxyVendor = true;

  preBuild = ''
    cmakeConfigurePhase
  '' + lib.optionalString (stdenv.buildPlatform != stdenv.hostPlatform) ''
    export GOARCH=$(go env GOHOSTARCH)
  '';

  env.NIX_CFLAGS_COMPILE = toString (lib.optionals stdenv.cc.isGNU [
    # Needed with GCC 12 but breaks on darwin (with clang)
    "-Wno-error=stringop-overflow"
  ]);

  buildPhase = ''
    ninjaBuildPhase
  '';

  cmakeFlags = [ "-GNinja" ] ++ lib.optionals (stdenv.hostPlatform.isLinux) [ "-DCMAKE_OSX_ARCHITECTURES=" ];

  installPhase = ''
    mkdir -p $bin/bin $dev $out/lib

    mv tool/bssl $bin/bin

    mv ssl/libssl.a           $out/lib
    mv crypto/libcrypto.a     $out/lib

    mv ../include $dev
  '';

  outputs = [ "out" "bin" "dev" ];

  meta = with lib; {
    description = "AWS-LC is a general-purpose cryptographic library maintained by the AWS Cryptography team for AWS and their customers. It іs based on code from the Google BoringSSL project and the OpenSSL project.";
    homepage = "https://github.com/aws/aws-lc";
    license = licenses.asl20;
    platforms = platforms.unix;
  };
}

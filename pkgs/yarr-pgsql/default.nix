{ source, lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  inherit (source) pname version src;

  vendorHash = "sha256-UbdK7itlqNyGKU/SBZHLubfch6puiXnVRzd2wwxXa5k=";

  ldflags = [ "-s" "-w" "-X main.Version=${version}" "-X main.GitHash=none" ];

  tags = [ "sqlite_foreign_keys" "release" ];

  # TODO: https://github.com/jgkawell/yarr/blob/v3.1.3/server/routes_test.go#L57
  # ":memory:" type is not supported by pgsql
  doCheck = false;

  meta = with lib; {
    description = "Yet another rss reader, pgsql fork";
    mainProgram = "yarr";
    homepage = "https://github.com/jgkawell/yarr";
    changelog = "https://github.com/jgkawell/yarr/blob/v${version}/doc/changelog.txt";
    license = licenses.mit;
    maintainers = with maintainers; [ sikmir ];
  };
}

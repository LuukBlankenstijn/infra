{ pkgs }:
let
  mkdocs = pkgs.python3.withPackages (ps: [ ps.mkdocs-material ]);
  src = pkgs.lib.fileset.toSource {
    root = ../../.;
    fileset = pkgs.lib.fileset.unions [
      ../../mkdocs.yml
      ../../docs
    ];
  };
in
pkgs.stdenvNoCC.mkDerivation {
  name = "infra-docs";
  inherit src;
  nativeBuildInputs = [ mkdocs ];
  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    mkdocs build --strict --site-dir "$out"
    runHook postBuild
  '';
  dontInstall = true;
}

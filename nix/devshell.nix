{ pkgs }:
pkgs.mkShellNoCC {
  name = "infra";
  packages = with pkgs; [
    age
    awscli2
    curl
    fluxcd
    jq
    k9s
    kubectl
    kubectl-cnpg
    kubernetes-helm
    kubeseal
    nixfmt
    nixos-rebuild
    openbao
    opentofu
    postgresql
    sops
    ssh-to-age
    yq-go
    (python3.withPackages (ps: [ ps.mkdocs-material ]))
  ];
}

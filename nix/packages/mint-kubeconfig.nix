{ pkgs }:
pkgs.writeShellApplication {
  name = "mint-kubeconfig";
  runtimeInputs = with pkgs; [
    kubectl
    coreutils
  ];
  text = ''
    root="$(git rev-parse --show-toplevel)"
    source_config="''${1:-$root/.kube/config}"
    server="https://192.168.1.78:6443"

    ca="$(kubectl --kubeconfig "$source_config" -n kube-system get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' | base64 -w0)"
    token="$(kubectl --kubeconfig "$source_config" -n kube-system create token infra-admin --duration=24h)"

    umask 077
    tmp="$(mktemp "$root/.kube/config.XXXXXX")"
    cat > "$tmp" <<EOF
    apiVersion: v1
    kind: Config
    clusters:
      - name: home
        cluster:
          server: $server
          certificate-authority-data: $ca
    users:
      - name: infra-admin
        user:
          token: $token
    contexts:
      - name: home
        context:
          cluster: home
          user: infra-admin
    current-context: home
    EOF
    mv "$tmp" "$root/.kube/config"
    echo "wrote $root/.kube/config (infra-admin, valid 24h)"
  '';
}

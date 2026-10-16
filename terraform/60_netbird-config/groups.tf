resource "netbird_group" "admins" {
  name = "admins"
}

resource "netbird_group" "servers" {
  name = "servers"
}

resource "netbird_group" "kubernetes_api" {
  name = "kubernetes-api"
}

resource "netbird_group" "ollama" {
  name = "ollama"
}

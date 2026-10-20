data "authentik_user" "luuk" {
  username = "luukblankenstijn"
}

resource "authentik_group" "infra_admins" {
  name  = "infra-admins"
  users = [data.authentik_user.luuk.id]
}

resource "authentik_group" "public" {
  name = "public"
}

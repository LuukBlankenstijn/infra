data "netbird_user" "luuk" {
  email = "me@luukblankenstijn.nl"
}

resource "netbird_user" "luuk" {
  email           = data.netbird_user.luuk.email
  name            = data.netbird_user.luuk.name
  role            = "admin"
  is_service_user = false
  auto_groups     = [data.netbird_group.admins.id]

  lifecycle {
    ignore_changes = [auto_groups]
  }
}

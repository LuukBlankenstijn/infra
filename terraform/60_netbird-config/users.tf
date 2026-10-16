data "netbird_user" "luuk" {
  email = "me@luukblankenstijn.nl"
}

import {
  to = netbird_user.luuk
  id = data.netbird_user.luuk.id
}

resource "netbird_user" "luuk" {
  email           = data.netbird_user.luuk.email
  name            = data.netbird_user.luuk.name
  role            = "admin"
  is_service_user = false
  auto_groups     = [netbird_group.admins.id]
}

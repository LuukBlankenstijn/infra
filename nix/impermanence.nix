# Impermanence temporarily disabled while we get the basic system booting.
# Re-add once SSH + Traefik + Zitadel/NetBird all come up cleanly.
#
# When re-enabling (tmpfs root), persist at least:
#   - /nix, /boot, ssh host keys
#   - /var/lib/postgresql        — Zitadel's real state lives here (encrypted
#                                  with the sops masterkey; persist BOTH or
#                                  neither, else the data is unreadable)
#   - /var/lib/zitadel           — holds the FirstInstance bootstrap PAT
#   - /var/lib/netbird-mgmt      — NetBird management store
#   - /var/lib/netbird-oidc      — generated Zitadel client ids/secret (tofu
#                                  re-delivers on a fresh deploy, so optional)
{ }

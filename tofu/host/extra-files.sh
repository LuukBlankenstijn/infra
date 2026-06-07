#!/usr/bin/env bash
# Runs in nixos-anywhere's working dir; anything written here is rsynced onto
# the target's `/` before install. Place the sops-nix host age key so the
# system can decrypt secrets on first boot.
set -euo pipefail

: "${HOST_AGE_KEY:?HOST_AGE_KEY must be set in extra_environment}"

install -d -m 0700 "$(pwd)/var/lib/sops-nix"
printf '%s' "$HOST_AGE_KEY" > "$(pwd)/var/lib/sops-nix/key.txt"
chmod 0400 "$(pwd)/var/lib/sops-nix/key.txt"

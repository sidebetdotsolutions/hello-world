#!/bin/bash


# this is for profile.d

SECRETS_FILE="$HOME/empire/hello-world/secrets/shared.env"

if [ -f "$SECRETS_FILE" ]; then
  eval "$(sops -d "$SECRETS_FILE" 2>/dev/null | sed 's/^/export /')"
fi

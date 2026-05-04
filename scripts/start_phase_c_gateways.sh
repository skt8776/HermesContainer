#!/usr/bin/env bash
set -euo pipefail

profiles=(pm researcher designer designbuilder softwarebuilder reviewer qa)

for profile in "${profiles[@]}"; do
  env_file="/home/hermes/.hermes/profiles/${profile}/.env"
  if [[ ! -f "$env_file" ]]; then
    echo "[$profile] missing profile env"
    continue
  fi

  token_line=$(grep '^DISCORD_BOT_TOKEN=' "$env_file" || true)
  token=${token_line#DISCORD_BOT_TOKEN=}
  if [[ -z "$token" || "$token" == REPLACE_WITH_* ]]; then
    echo "[$profile] skipped (no bot token configured)"
    continue
  fi

  echo "[$profile] starting gateway"
  nohup hermes --profile "$profile" gateway run >/tmp/hermes-gateway-${profile}.log 2>&1 &
  sleep 2
  pgrep -af "hermes --profile ${profile} gateway run" || true
  echo
 done

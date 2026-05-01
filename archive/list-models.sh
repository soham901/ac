#!/bin/bash

CONFIG_DIR="$HOME/.config/ac"

spinner_inline() {
  local pid=$1
  local delay=0.15
  while [ -d /proc/$pid ]; do
    echo -ne "\r[..] " && sleep $delay
    echo -ne "\r[...]" && sleep $delay
  done
  echo -ne "\r[OK] "
}

# Fetch models if cache doesn't exist
if [ ! -f "$CONFIG_DIR/models.json" ]; then
  echo -n "Fetching models list... "
  mkdir -p "$CONFIG_DIR"
  (
    models_json=$(curl -s --max-time 15 "https://openrouter.ai/api/v1/models" 2>/dev/null)
    if [ -z "$models_json" ]; then
      echo "❌ Error: Could not fetch models from API" >&2
      exit 1
    fi
    echo "$models_json" > "$CONFIG_DIR/models.json"
  ) &
  
  spinner_inline $!
  wait $!
  exit_code=$?
  
  if [ $exit_code -ne 0 ]; then
    echo ""
    echo "[ERROR] Failed to fetch models. Check your internet connection."
    exit 1
  fi
  echo "Done"
fi

# Handle flags
if [ "$1" = "--names" ] || [ "$1" = "-n" ]; then
  cat "$CONFIG_DIR/models.json" | jq -r '.data[].id' | sort | tr '\n' ' ' | sed 's/ $//'
  echo ""
elif [ "$1" = "--free" ] || [ "$1" = "-f" ]; then
  cat "$CONFIG_DIR/models.json" | jq -r '.data[] | select(.pricing.prompt == 0 and .pricing.completion == 0) | .id' | sort | tr '\n' ' ' | sed 's/ $//'
  echo ""
else
  echo "════════════════════════════════════════"
  echo "  Available Free Models (OpenRouter)"
  echo "════════════════════════════════════════"
  echo ""

  cat "$CONFIG_DIR/models.json" | jq -r '.data[] | select(.pricing.prompt == 0 and .pricing.completion == 0) | .id' | sort | nl

  echo ""
  total=$(cat "$CONFIG_DIR/models.json" | jq '[.data[] | select(.pricing.prompt == 0 and .pricing.completion == 0)] | length')
  echo "Total: $total free models"
  echo ""
fi

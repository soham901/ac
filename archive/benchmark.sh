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

# Ensure models cache exists
if [ ! -f "$CONFIG_DIR/models.json" ]; then
  echo -n "Fetching models list... "
  mkdir -p "$CONFIG_DIR"
  (
    models_json=$(curl -s --max-time 15 "https://openrouter.ai/api/v1/models" 2>/dev/null)
    if [ -z "$models_json" ]; then
      echo "[ERROR] Could not fetch models from API" >&2
      exit 1
    fi
    echo "$models_json" > "$CONFIG_DIR/models.json"
  ) &
  
  spinner_inline $!
  wait $!
  exit_code=$?
  
  if [ $exit_code -ne 0 ]; then
    echo ""
    echo "[ERROR] Failed to fetch models."
    exit 1
  fi
  echo "Done"
fi

# Get models from arguments or use defaults
if [ $# -eq 0 ]; then
  echo "Usage: benchmark.sh <model1> <model2> ..."
  echo ""
  echo "Examples:"
  echo "  ./benchmark.sh mistral-7b-instruct-free gpt-3.5-turbo llama-2-7b-free"
  echo ""
  echo "Available free models:"
  cat "$CONFIG_DIR/models.json" | jq -r '.data[] | select(.pricing.prompt == 0 and .pricing.completion == 0) | .id' | sort | column
  exit 0
fi

MODELS=("$@")

echo "════════════════════════════════════════"
echo "  AC Benchmark - Model Speed Test"
echo "════════════════════════════════════════"
echo ""
echo "Testing ${#MODELS[@]} model(s) for commit message generation..."
echo ""
echo "Model                          Time (s)   Status"
echo "─────────────────────────────────────────────────"

RESULTS=()

if [ -z "$OPENROUTER_API_KEY" ]; then
  echo "[ERROR] OPENROUTER_API_KEY not set"
  echo "Set it with: export OPENROUTER_API_KEY=your_key"
  exit 1
fi

for model in $MODELS; do
  echo -n "Testing $model... " >&2
  start_time=$(date +%s.%N)
  
  # Test with simple prompt (60s timeout)
  result=$(timeout 60 curl -s "https://openrouter.ai/api/v1/chat/completions" \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"$model\",
      \"messages\": [{\"role\": \"user\", \"content\": \"Generate a 1-word commit message. Return ONLY the word.\"}],
      \"temperature\": 0.7
    }" 2>&1)
  exit_code=$?
  
  end_time=$(date +%s.%N)
  duration=$(echo "$end_time - $start_time" | bc)
  
  # Format output
  status="[OK]"
  if [ $exit_code -eq 124 ]; then
    status="[TIMEOUT 60s]"
    duration="60.0"
  elif echo "$result" | grep -q "error"; then
    status="[ERROR]"
    duration="N/A"
  elif [ $exit_code -ne 0 ]; then
    status="[ERROR $exit_code]"
    duration="N/A"
  fi
  
  echo "done ($duration s)" >&2
  if [ "$duration" = "N/A" ]; then
    printf "%-30s %8s   %s\n" "$model" "$duration" "$status"
  else
    printf "%-30s %8.2f   %s\n" "$model" "$duration" "$status"
  fi
  
  RESULTS+=("$model|$duration|$status")
done

echo ""
echo "════════════════════════════════════════"
echo "  Results Summary"
echo "════════════════════════════════════════"
echo ""

# Sort by speed
IFS=$'\n' sorted=($(sort -t'|' -k2 -n <<<"${RESULTS[*]}"))
unset IFS

echo "All Models (sorted by speed):"
echo ""
printf "%-30s %8s   %s\n" "Model" "Time (s)" "Status"
echo "─────────────────────────────────────────────────"

count=0
for result in "${sorted[@]}"; do
  IFS='|' read -r model duration status <<< "$result"
  if [ "$duration" = "N/A" ]; then
    printf "%-30s %8s   %s\n" "$model" "$duration" "$status"
  else
    printf "%-30s %8.2f   %s\n" "$model" "$duration" "$status"
  fi
done

echo ""
echo "Recommendation: Use the fastest working model"
echo ""

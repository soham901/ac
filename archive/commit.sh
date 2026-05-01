#!/bin/bash

CONFIG_DIR="$HOME/.config/ac"
CONFIG_FILE="$CONFIG_DIR/config"

ensure_models_cache() {
  if [ ! -f "$CONFIG_DIR/models.json" ]; then
    echo "Fetching available models..."
    mkdir -p "$CONFIG_DIR"
    models_json=$(curl -s "https://openrouter.ai/api/v1/models" 2>/dev/null)
    if [ -z "$models_json" ]; then
      echo "Could not fetch models from API"
      return 1
    fi
    echo "$models_json" > "$CONFIG_DIR/models.json"
  fi
  return 0
}

init_config() {
  mkdir -p "$CONFIG_DIR"
  
  echo "════════════════════════════════════════"
  echo "  First-time setup for 'ac' command"
  echo "════════════════════════════════════════"
  echo ""
  
  if ! ensure_models_cache; then
    echo "Using default: openrouter/free"
    model="openrouter/free"
  else
    models_json=$(cat "$CONFIG_DIR/models.json")
    
    echo "Available free models:"
    echo ""
    # Parse and display free models only
    free_models=$(echo "$models_json" | jq -r '.data[] | select(.pricing.prompt == 0 and .pricing.completion == 0) | .id' | sort)
    echo "$free_models" | nl
    echo ""
    read -p "Enter model number or custom model ID: " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      # Extract model by number
      model=$(echo "$free_models" | sed -n "${choice}p")
      if [ -z "$model" ]; then
        echo "Invalid selection. Using default: openrouter/free"
        model="openrouter/free"
      fi
    elif [ -n "$choice" ]; then
      # Custom model ID
      model="$choice"
    else
      echo "Using default: openrouter/free"
      model="openrouter/free"
    fi
  fi
  
  echo "MODEL=$model" > "$CONFIG_FILE"
  echo ""
  echo "[OK] Config saved to $CONFIG_FILE (MODEL=$model)"
  echo "  To change model later, run: ac --config"
  echo ""
}

load_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    init_config
  fi
  source "$CONFIG_FILE"
}

show_config() {
  echo "Current config:"
  cat "$CONFIG_FILE"
  echo ""
  read -p "Enter new model ID (or press Enter to keep current): " new_model
  if [ -n "$new_model" ]; then
    echo "MODEL=$new_model" > "$CONFIG_FILE"
    echo "[OK] Config updated"
  fi
  exit 0
}

# Handle --config flag
if [ "$1" = "--config" ] || [ "$1" = "-c" ]; then
  load_config
  show_config
fi

load_config

STAGED_SUMMARY=$(git diff --staged --stat | head -n -1)

if [ -z "$STAGED_SUMMARY" ]; then
  echo "No staged changes. Run 'git add' first."
  exit 1
fi

show_spinner() {
  local pid=$1
  local delay=0.15
  while [ -d /proc/$pid ]; do
    echo -ne "\r[..] " && sleep $delay
    echo -ne "\r[...]" && sleep $delay
  done
  echo -ne "\r"
}

generate_message() {
  local feedback="${1:-}"
  
  if [ -z "$OPENROUTER_API_KEY" ]; then
    echo "[ERROR] OPENROUTER_API_KEY not set" >&2
    echo "Set it with: export OPENROUTER_API_KEY=your_key" >&2
    echo "Get your key at: https://openrouter.ai/keys" >&2
    return 1
  fi
  
  # Get diff and filter long files
  local diff_content=$(git diff --staged)
  local filtered_diff=""
  local file_lines=0
  local max_lines=30
  local in_file=false
  
  while IFS= read -r line; do
    if [[ "$line" =~ ^diff\ --git ]]; then
      in_file=true
      file_lines=0
      filtered_diff+="$line"$'\n'
    elif [[ "$line" =~ ^@@.*@@ ]]; then
      ((file_lines++))
      if [ $file_lines -lt $max_lines ]; then
        filtered_diff+="$line"$'\n'
      elif [ $file_lines -eq $max_lines ]; then
        filtered_diff+="[file truncated]"$'\n'
      fi
    elif [ $file_lines -lt $max_lines ]; then
      filtered_diff+="$line"$'\n'
      ((file_lines++))
    fi
  done <<< "$diff_content"
  
  # Escape diff for JSON
  local escaped_diff=$(echo "$filtered_diff" | jq -Rs '.')
  
  prompt="Analyze these staged changes and return a SINGLE commit message word.

RULES: (1) 1 word only. (2) lowercase. (3) Types: fix,feat,chores,docs,refactor,init,test,update. (4) No punctuation, no explanation. ONLY THE WORD."
  
  if [ -n "$feedback" ]; then
    prompt="$prompt Feedback: $feedback"
  fi
  
  local payload=$(jq -n \
    --arg model "$MODEL" \
    --arg content "$prompt" \
    --arg changes "$filtered_diff" \
    '{
      model: $model,
      messages: [{
        role: "user",
        content: ($content + "\n\nChanges:\n" + $changes)
      }],
      temperature: 0.7,
      top_p: 1
    }')
  
  response=$(curl -s --max-time 30 "https://openrouter.ai/api/v1/chat/completions" \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null)
  
  if echo "$response" | grep -q "error"; then
    error_msg=$(echo "$response" | jq -r '.error.message // .error' 2>/dev/null)
    echo "[ERROR] API Error: $error_msg" >&2
    return 1
  fi
  
  message=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  
  if [ -z "$message" ]; then
    echo "[ERROR] Failed to generate message" >&2
    return 1
  fi
  
  # Extract only the first word
  message=$(echo "$message" | awk '{print $1}' | tr -d '.:,;!?\n' | tr '[:upper:]' '[:lower:]')
  
  echo "$message"
}

while true; do
  COMMIT_MSG=$(generate_message)
  
  if [ -z "$COMMIT_MSG" ]; then
    continue
  fi
  
  echo "Staged changes:"
  echo "$STAGED_SUMMARY"
  echo "Message: $COMMIT_MSG"
  
  while true; do
    read -p "Accept? (a/e/r/q): " -n 1 choice
    echo ""
    
    case $choice in
      [aA])
        git commit -m "$COMMIT_MSG"
        echo "[OK] Committed: $COMMIT_MSG"
        exit 0
        ;;
      [eE])
        echo "$COMMIT_MSG" > /tmp/commit_msg.tmp
        EDITOR=$(git config --get core.editor)
        if [ -z "$EDITOR" ]; then
          if command -v vim &> /dev/null; then
            EDITOR="vim"
          elif command -v vi &> /dev/null; then
            EDITOR="vi"
          else
            EDITOR="nano"
          fi
        fi
        $EDITOR /tmp/commit_msg.tmp
        COMMIT_MSG=$(cat /tmp/commit_msg.tmp)
        rm -f /tmp/commit_msg.tmp
        git commit -m "$COMMIT_MSG"
        echo "[OK] Committed: $COMMIT_MSG"
        exit 0
        ;;
      [rR])
        read -p "Feedback (optional): " feedback_input
        if [ -n "$feedback_input" ]; then
          COMMIT_MSG=$(generate_message "$feedback_input")
        else
          COMMIT_MSG=$(generate_message)
        fi
        echo ""
        break
        ;;
      [qQ])
        echo "[CANCELLED]"
        exit 1
        ;;
      *)
        echo "[INVALID] Choose: a, e, r, or q"
        ;;
    esac
  done
done

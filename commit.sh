#!/bin/bash

CONFIG_DIR="$HOME/.config/ac"
CONFIG_FILE="$CONFIG_DIR/config"

init_config() {
  mkdir -p "$CONFIG_DIR"
  
  echo "════════════════════════════════════════"
  echo "  First-time setup for 'ac' command"
  echo "════════════════════════════════════════"
  echo ""
  echo "Fetching available models (this may take a moment)..."
  
  # Fetch models from endpoint
  models_json=$(curl -s "https://opencode.ai/zen/v1/models" 2>/dev/null)
  
  if [ -z "$models_json" ]; then
    echo "Could not fetch models. Using default: minimax-m2.5-free"
    model="minimax-m2.5-free"
  else
    # Cache the models list
    echo "$models_json" > "$CONFIG_DIR/models.json"
    
    echo "Available models:"
    echo ""
    # Parse and display models
    echo "$models_json" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | nl
    echo ""
    read -p "Enter model number or custom model ID: " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      # Extract model by number
      model=$(echo "$models_json" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | sed -n "${choice}p")
      if [ -z "$model" ]; then
        echo "Invalid selection. Using default: minimax-m2.5-free"
        model="minimax-m2.5-free"
      fi
    elif [ -n "$choice" ]; then
      # Custom model ID
      model="$choice"
    else
      echo "Using default: minimax-m2.5-free"
      model="minimax-m2.5-free"
    fi
  fi
  
  echo "MODEL=$model" > "$CONFIG_FILE"
  echo ""
  echo "✓ Config saved to $CONFIG_FILE (MODEL=$model)"
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
    echo "✓ Config updated"
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

generate_message() {
  # Convert model ID to provider/model format if needed
  if [[ "$MODEL" == *"/"* ]]; then
    model_arg="$MODEL"
  else
    model_arg="opencode/$MODEL"
  fi
  opencode run -m "$model_arg" "Generate a commit message for these staged changes. RULES: (1) Return ONLY 1 word, no more. (2) Use ONLY lowercase. (3) Common types: 'fix', 'chores', 'feat', 'docs', 'refactor', 'init', 'test', 'update'. (4) Return ONLY the word itself, nothing else—no explanation, no punctuation, no markdown. Examples: 'fix', 'chores', 'feat'."
}

attempt=1
while true; do
  COMMIT_MSG=$(generate_message)
  
  echo "════════════════════════════════════════"
  echo "Staged changes:"
  echo "────────────────────────────────────────"
  echo "$STAGED_SUMMARY"
  echo "════════════════════════════════════════"
  echo ""
  echo "Proposed commit message:"
  echo "  $COMMIT_MSG"
  echo ""
  echo "Options: (a)ccept, (e)dit, (r)egenerate, (q)uit"
  read -p "Choose: " -n 1 choice
  echo ""
  
  case $choice in
    [aA])
      git commit -m "$COMMIT_MSG"
      echo "✓ Committed"
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
      echo "✓ Committed"
      exit 0
      ;;
    [rR])
      ((attempt++))
      echo ""
      ;;
    [qQ])
      echo "Cancelled"
      exit 1
      ;;
    *)
      echo "Invalid choice"
      ;;
  esac
done

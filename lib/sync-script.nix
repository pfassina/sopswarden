{ secrets, sopsFile, ageKeyFile, sopsConfigFile, rbwCommand, forceSync, workingDirectory }:

let
  forceSyncFlag = if forceSync then "true" else "false";
  # Convert secrets to JSON for the script to read
  secretsJson = builtins.toJSON secrets;
in
''
  #!/usr/bin/env bash
  # sopswarden-sync - Sync secrets from Bitwarden to encrypted sops file

  set -euo pipefail

  # Configuration
  SOPS_FILE="${sopsFile}" 
  AGE_KEY_FILE="${ageKeyFile}"
  SOPS_CONFIG_FILE="${sopsConfigFile}"
  RBW_COMMAND="${rbwCommand}"
  FORCE_SYNC="${forceSyncFlag}"
  WORKING_DIR="${workingDirectory}"

  # Expand ~ in paths
  SOPS_FILE="''${SOPS_FILE/#\~/$HOME}"
  SOPS_CONFIG_FILE="''${SOPS_CONFIG_FILE/#\~/$HOME}"
  AGE_KEY_FILE="''${AGE_KEY_FILE/#\~/$HOME}"

  # Create parent directories if they don't exist
  mkdir -p "$(dirname "$SOPS_FILE")"
  mkdir -p "$(dirname "$AGE_KEY_FILE")"
  mkdir -p "$WORKING_DIR"

  # Work from the correct directory
  cd "$WORKING_DIR"

  # Check if secrets configuration has changed since last sync
  SECRETS_CONFIG='${secretsJson}'
  SECRETS_HASH=$(echo -n "$SECRETS_CONFIG" | sha256sum | cut -d' ' -f1)
  LAST_HASH_FILE="$WORKING_DIR/.last-sync-hash"

  if [ "$FORCE_SYNC" != "true" ] && [ -f "$LAST_HASH_FILE" ] && [ "$(cat "$LAST_HASH_FILE")" = "$SECRETS_HASH" ]; then
      echo "✅ secrets configuration unchanged since last sync, skipping..."
      echo "💡 Use FORCE_SYNC=true to force a sync anyway"
      exit 0
  fi

  # Check if rbw is available and authenticated
  if ! command -v "$RBW_COMMAND" &> /dev/null; then
      echo "Error: rbw is not installed. Please install it first."
      exit 1
  fi

  # Check if sops is available
  if ! command -v sops &> /dev/null; then
      echo "Error: sops is not installed. Please install it first."
      exit 1
  fi

  # Test rbw authentication
  if ! "$RBW_COMMAND" ls &> /dev/null; then
      echo "Error: rbw is not authenticated. Please run 'rbw login' first."
      exit 1
  fi

  echo "🔄 Syncing secrets from Bitwarden..."

  # Extract secret keys from the configuration
  secret_keys=$(echo "$SECRETS_CONFIG" | jq -r 'keys[]')

  # Create temporary unencrypted YAML
  temp_file=$(mktemp)
  echo "# Auto-generated from Bitwarden - $(date)" > "$temp_file"

  for key in $secret_keys; do
      echo "📡 Fetching: $key"
    
      # Get the secret definition (either string or object)
      secret_def=$(echo "$SECRETS_CONFIG" | jq -c ".$key")
    
      # Parse the definition
      if echo "$secret_def" | jq -e 'type == "string"' >/dev/null; then
          # Simple string definition
          name=$(echo "$secret_def" | jq -r '.')
          user=""
          item_type="login"
          field="password"
      else
          # Complex object definition
          name=$(echo "$secret_def" | jq -r '.name')
          user=$(echo "$secret_def" | jq -r '.user // empty')
          item_type=$(echo "$secret_def" | jq -r '.type // "login"')
          field=$(echo "$secret_def" | jq -r '.field // "password"')
      fi
    
      # Fetch from bitwarden based on type
      if [ "$item_type" = "note" ]; then
          # For secure notes, use --field to get specific field
          secret_value=$("$RBW_COMMAND" get "$name" --field "$field")
      elif [ -n "$user" ]; then
          # For login items with specific user
          if [ "$field" = "password" ]; then
              secret_value=$("$RBW_COMMAND" get "$name" "$user")
          else
              secret_value=$("$RBW_COMMAND" get "$name" "$user" --field "$field")
          fi
      else
          # For login items without specific user
          if [ "$field" = "password" ]; then
              secret_value=$("$RBW_COMMAND" get "$name")
          else
              secret_value=$("$RBW_COMMAND" get "$name" --field "$field")
          fi
      fi
    
      # Add to YAML (escape special characters)
      echo "$key: \"$secret_value\"" >> "$temp_file"
  done

  # Encrypt with sops and place in the correct location
  if [ -f "$SOPS_FILE" ]; then
      echo "🔒 Updating existing encrypted secrets file..."
  else
      echo "🔒 Creating new encrypted secrets file..."
  fi

  # Ensure .sops.yaml exists and has the right age key
  if [ ! -f "$SOPS_CONFIG_FILE" ]; then
      # Generate age key if it doesn't exist
      if [ ! -f "$AGE_KEY_FILE" ]; then
          echo "🔑 Generating new age key..."
          mkdir -p "$(dirname "$AGE_KEY_FILE")"
          age-keygen -o "$AGE_KEY_FILE"
      fi
    
      # Get the public key
      AGE_PUBLIC_KEY=$(age-keygen -y "$AGE_KEY_FILE")
    
      echo "📝 Creating .sops.yaml configuration..."
      cat > "$SOPS_CONFIG_FILE" << EOF
  creation_rules:
    - path_regex: .*\.yaml$
      age: $AGE_PUBLIC_KEY
  EOF
  fi

  # Encrypt with sops
  sops --encrypt "$temp_file" > "$SOPS_FILE"
  rm "$temp_file"

  # Update the hash file to track this sync
  echo -n "$SECRETS_HASH" > "$LAST_HASH_FILE"

  echo "✅ Secrets synced successfully to $SOPS_FILE"
  echo "📝 Remember to commit the updated secrets file if needed"
''
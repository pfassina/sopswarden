{ secretsFile, sopsFile, ageKeyFile, sopsConfigFile, rbwCommand, forceSync, workingDirectory }:

let
  forceSyncFlag = if forceSync then "true" else "false";
in
''
  #!/usr/bin/env bash
  # sopswarden-sync - Sync secrets from Bitwarden to encrypted sops file

  set -euo pipefail

  # Configuration
  SECRETS_FILE="${secretsFile}"
  SOPS_FILE="${sopsFile}" 
  AGE_KEY_FILE="${ageKeyFile}"
  SOPS_CONFIG_FILE="${sopsConfigFile}"
  RBW_COMMAND="${rbwCommand}"
  FORCE_SYNC="${forceSyncFlag}"
  WORKING_DIR="${if workingDirectory != null then workingDirectory else "$(dirname \"$SECRETS_FILE\")"}"

  # Expand ~ in paths
  SECRETS_FILE="''${SECRETS_FILE/#\~/$HOME}"
  SOPS_FILE="''${SOPS_FILE/#\~/$HOME}"
  SOPS_CONFIG_FILE="''${SOPS_CONFIG_FILE/#\~/$HOME}"
  AGE_KEY_FILE="''${AGE_KEY_FILE/#\~/$HOME}"

  # Create parent directories if they don't exist
  mkdir -p "$(dirname "$SOPS_FILE")"
  mkdir -p "$(dirname "$AGE_KEY_FILE")"

  # Work from the correct directory
  cd "$WORKING_DIR"

  # Check if secrets.nix has changed since last sync
  SECRETS_HASH=$(sha256sum "$SECRETS_FILE" 2>/dev/null | cut -d' ' -f1 || echo "no-hash")
  LAST_HASH_FILE="$(dirname "$SECRETS_FILE")/.last-sync-hash"

  if [ "$FORCE_SYNC" != "true" ] && [ -f "$LAST_HASH_FILE" ] && [ "$(cat "$LAST_HASH_FILE")" = "$SECRETS_HASH" ]; then
      echo "✅ secrets file unchanged since last sync, skipping..."
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

  # Read secrets.nix and extract secret definitions using nix
  secret_keys=$(nix eval --impure --raw --expr "
    let secrets = (import $SECRETS_FILE).secrets or (import $SECRETS_FILE); 
    in builtins.concatStringsSep \" \" (builtins.attrNames secrets)")

  # Create temporary unencrypted YAML
  temp_file=$(mktemp)
  echo "# Auto-generated from Bitwarden - $(date)" > "$temp_file"

  for key in $secret_keys; do
      echo "📡 Fetching: $key"
    
      # Get the secret definition (either string or attrset)
      secret_def=$(nix eval --impure --raw --expr "
          let secrets = (import $SECRETS_FILE).secrets or (import $SECRETS_FILE);
              def = secrets.$key;
          in if builtins.isString def then 
              builtins.toJSON { name = def; user = null; type = \"login\"; field = \"password\"; }
          else 
              builtins.toJSON (def // { type = def.type or \"login\"; field = def.field or \"password\"; })")
    
      # Parse the JSON to get all fields
      name=$(echo "$secret_def" | jq -r '.name')
      user=$(echo "$secret_def" | jq -r '.user // empty')
      item_type=$(echo "$secret_def" | jq -r '.type // "login"')
      field=$(echo "$secret_def" | jq -r '.field // "password"')
    
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
  echo "📝 Remember to commit the updated secrets file"
''

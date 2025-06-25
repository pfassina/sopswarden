# scripts/rewrite-system.nix
{ placeholders, lib }:

let
  # Convert the attr-set into a list of "token|file" pairs at *Nix* time
  pairs = lib.mapAttrsToList
    (token: file: "${token}|${file}")
    placeholders;
in
''
  set -e
  echo "🔄 Sopswarden: substituting secret sentinels in system files..."

  # Iterate over the static list produced above
  for pair in ${lib.escapeShellArgs pairs}; do
    token=''${pair%%|*}       # token is left of the first "|"
    secretFile=''${pair#*|}   # path  is right of the first "|"

    echo "  🔍 Processing token: $token -> $secretFile"
    
    if [ ! -f "$secretFile" ]; then
      echo "  ⚠️  Secret file not found: $secretFile"
      continue
    fi
    
    secretValue=$(cat "$secretFile")
    echo "  ✓ Read secret value (''${#secretValue} chars)"

    # Search for files containing the token - simplified approach
    echo "  🔍 Searching for files containing: $token"
    found_files=0
    
    # Look in common config locations
    for search_dir in /etc/nixos /etc; do
      if [ -d "$search_dir" ]; then
        find "$search_dir" -type f -name "*.conf" -o -name "*.config" -o -name "*config*" 2>/dev/null | while read -r f; do
          if [ -f "$f" ] && ! [[ "$(realpath "$f" 2>/dev/null || echo "$f")" == /nix/store/* ]]; then
            if grep -q "$token" "$f" 2>/dev/null; then
              echo "  📝 Substituting $token in $f"
              sed -i "s|$token|$secretValue|g" "$f" || echo "  ⚠️  Failed to substitute in $f"
              found_files=$((found_files + 1))
            fi
          fi
        done
      fi
    done
  done

  echo "✅ Sopswarden: system secret substitution complete"
''
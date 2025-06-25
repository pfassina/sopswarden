# modules/hm-rewrite.nix - Home Manager secret substitution module
{ lib, placeholders ? {} }:

let
  # Convert the attr-set into a list of "token|file" pairs at *Nix* time
  # Handle case where placeholders might be empty
  pairs = if placeholders == {} then [] else lib.mapAttrsToList
    (token: file: "${token}|${file}")
    placeholders;
in
{
  home.activation.sopswarden-rewrite = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -e
    echo "🔄 Sopswarden: substituting secret sentinels in home files..."
    
    # Try to get placeholders from multiple sources
    placeholders_json=""
    
    # Method 1: From environment variable (standalone HM)
    if [ -n "''${SOPSWARDEN_PLACEHOLDERS:-}" ]; then
      placeholders_json="$SOPSWARDEN_PLACEHOLDERS"
      echo "  📥 Found placeholders in environment variable"
    # Method 2: From system file
    elif [ -f "/etc/sopswarden/placeholders.json" ]; then
      placeholders_json=$(cat /etc/sopswarden/placeholders.json)
      echo "  📥 Found placeholders in /etc/sopswarden/placeholders.json"
    # Method 3: From Nix-provided data (NixOS-style HM)
    elif [ ${toString (builtins.length pairs)} -gt 0 ]; then
      echo "  📥 Using Nix-provided placeholders (${toString (builtins.length pairs)} items)"
      # Use the static pairs from Nix evaluation
      ${lib.concatStringsSep "\n" (map (pair: ''
        token=''${pair%%|*}
        secretFile=''${pair#*|}
        if [ -f "$secretFile" ]; then
          val=$(cat "$secretFile")
          find "$HOME" -xtype f -not -path "$HOME/.nix-profile/*" -name ".*" -o -name "*.conf" -o -name "*.config" 2>/dev/null | while read -r f; do
            if [ -f "$f" ] && grep -q "$token" "$f" 2>/dev/null; then
              echo "  📝 Substituting $token in $f"
              sed -i "s|$token|$val|g" "$f" || true
            fi
          done
        fi
      '') pairs)}
      echo "✅ Sopswarden: home secret substitution complete"
      exit 0
    else
      echo "  ⚠️  No sopswarden placeholders found - skipping substitution"
      exit 0
    fi
    
    # Parse JSON placeholders (for methods 1 & 2)
    if [ -n "$placeholders_json" ]; then
      echo "$placeholders_json" | while IFS= read -r line; do
        # Simple JSON parsing for {"token": "file"} format
        token=$(echo "$line" | sed -n 's/.*"\([^"]*\)": *"\([^"]*\)".*/\1/p')
        secretFile=$(echo "$line" | sed -n 's/.*"\([^"]*\)": *"\([^"]*\)".*/\2/p')
        
        if [ -n "$token" ] && [ -n "$secretFile" ] && [ -f "$secretFile" ]; then
          val=$(cat "$secretFile")
          find "$HOME" -xtype f -not -path "$HOME/.nix-profile/*" -name ".*" -o -name "*.conf" -o -name "*.config" 2>/dev/null | while read -r f; do
            if [ -f "$f" ] && grep -q "$token" "$f" 2>/dev/null; then
              echo "  📝 Substituting $token in $f"
              sed -i "s|$token|$val|g" "$f" || true
            fi
          done
        fi
      done
    fi
    
    echo "✅ Sopswarden: home secret substitution complete"
  '';
}
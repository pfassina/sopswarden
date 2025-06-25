# scripts/rewrite-system.nix
{ placeholders, lib }:

let
  # Convert the attr-set into a list of "token|file" pairs at *Nix* time
  pairs = lib.mapAttrsToList
    (token: file: "${token}|${file}")
    placeholders;
in
''
  set -eo pipefail
  echo "🔄 Sopswarden: substituting secret sentinels in system files..."

  # Iterate over the static list produced above
  for pair in ${lib.escapeShellArgs pairs}; do
    token=''${pair%%|*}       # token is left of the first "|"
    secretFile=''${pair#*|}   # path  is right of the first "|"

    [ -f "$secretFile" ] || continue
    secretValue=$(cat "$secretFile")

    # Search only writable regular files under /etc
    find /etc -xtype f ! -path "/etc/static/*" -print0 2>/dev/null |
      xargs -0 grep -lZ "$token" 2>/dev/null |
      while IFS= read -r -d '' f; do
        # Skip if real target lives inside /nix/store
        if [[ "$(realpath "$f")" == /nix/store/* ]]; then
          echo "  ⚠️  Skip read-only $f"
          continue
        fi
        echo "  📝 Substituting $token in $f"
        sed -i "s|$token|$secretValue|g" "$f"
      done
  done

  echo "✅ Sopswarden: system secret substitution complete"
''
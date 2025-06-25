# modules/hm-rewrite.nix - Home Manager secret substitution module
{ lib, placeholders }:

let
  # Convert the attr-set into a list of "token|file" pairs at *Nix* time
  pairs = lib.mapAttrsToList
    (token: file: "${token}|${file}")
    placeholders;
in
{
  home.activation.sopswarden-rewrite = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -eo pipefail
    echo "🔄 Sopswarden: substituting secret sentinels in home files..."
    
    # Iterate over the static list produced above
    for pair in ${lib.escapeShellArgs pairs}; do
      token=''${pair%%|*}       # token is left of the first "|"
      secretFile=''${pair#*|}   # path  is right of the first "|"
      
      [ -f "$secretFile" ] || continue
      val=$(cat "$secretFile")
      find "$HOME" -xtype f -not -path "$HOME/.nix-profile/*" -print0 2>/dev/null |
        xargs -0 grep -lZ "$token" 2>/dev/null |
        while IFS= read -r -d '' f; do
          echo "  📝 Substituting $token in $f"
          sed -i "s|$token|$val|g" "$f"
        done
    done
    echo "✅ Sopswarden: home secret substitution complete"
  '';
}
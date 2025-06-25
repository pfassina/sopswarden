# modules/hm-module.nix - Home Manager mini-module injected automatically
{ lib, placeholders }:
{
  # pass map to HM activation step
  _module.args.placeholders = placeholders;

  home.activation.sopswarden-rewrite =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -eo pipefail
      echo "🔄 Sopswarden: substituting secret sentinels in home files..."
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (token: file: ''
        if [ -f "${file}" ]; then
          val=$(cat "${file}")
          grep -RlZ -- "${token}" "$HOME" 2>/dev/null |
          while IFS= read -r -d $'\0' f; do
            echo "  📝 Substituting ${token} in $f"
            sed -i "s|${token}|$val|g" "$f"
          done
        fi
      '') placeholders)}
      echo "✅ Sopswarden: home secret substitution complete"
    '';
}
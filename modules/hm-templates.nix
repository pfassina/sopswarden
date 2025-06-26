# Home Manager SOPS template integration
# Automatically detects Home Manager files with SOPS placeholders and converts them to templates

{ lib, config, pkgs, ... }:

let
  # Helper to detect if a string contains SOPS placeholders
  hasSopsPlaceholder = text: 
    builtins.isString text && 
    (lib.hasInfix "\${config.sops.placeholder." text);

  # Get files with SOPS placeholders from home.file
  filesWithPlaceholders = lib.filterAttrs 
    (name: fileConfig: 
      fileConfig ? text && hasSopsPlaceholder fileConfig.text
    ) 
    (config.home.file or {});

  # Generate SOPS templates for files with placeholders
  sopsTemplates = lib.mapAttrs'
    (fileName: fileConfig: {
      name = "hm-${builtins.replaceStrings ["/"] ["-"] fileName}";
      value = {
        content = fileConfig.text;
        owner = config.home.username;
        group = "users";
      };
    })
    filesWithPlaceholders;

  # Generate activation script to link templates to their final locations
  activationScript = lib.optionalString (filesWithPlaceholders != {}) ''
    echo "🔗 Sopswarden: linking Home Manager SOPS templates..."
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList
      (fileName: fileConfig: 
        let
          targetPath = "${config.home.homeDirectory}/${fileName}";
          templateName = "hm-${builtins.replaceStrings ["/"] ["-"] fileName}";
        in ''
          if [[ -f "/run/secrets/${templateName}" ]]; then
            mkdir -p "$(dirname "${targetPath}")"
            ln -sf "/run/secrets/${templateName}" "${targetPath}"
            echo "  ✓ ${fileName} -> /run/secrets/${templateName}"
          else
            echo "  ⚠️  Template not found: /run/secrets/${templateName}"
          fi
        ''
      )
      filesWithPlaceholders
    )}
    echo "✅ Sopswarden: Home Manager template linking complete"
  '';

in {
  # Export SOPS templates to be used by the NixOS SOPS configuration
  _module.args.sopswarden-hm-templates = sopsTemplates;

  # Disable files with placeholders to avoid conflicts
  home.file = lib.mapAttrs'
    (fileName: fileConfig: {
      name = fileName;
      value = lib.mkForce { enable = false; };
    })
    filesWithPlaceholders;

  # Add activation script to link templates
  home.activation.sopswarden-template-linking = lib.hm.dag.entryAfter ["writeBoundary"] activationScript;

  # Provide informative warnings
  warnings = lib.optional (filesWithPlaceholders != {}) 
    "sopswarden: Detected ${toString (builtins.length (builtins.attrNames filesWithPlaceholders))} Home Manager files with SOPS placeholders: ${lib.concatStringsSep ", " (builtins.attrNames filesWithPlaceholders)}. Templates will be generated and linked automatically.";
}
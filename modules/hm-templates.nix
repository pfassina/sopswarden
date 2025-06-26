# Home Manager SOPS template integration
# Automatically detects Home Manager files with SOPS placeholders and converts them to templates

{ lib, config, pkgs, ... }:

let
  # Helper to detect if a string contains SOPS placeholders
  hasSopsPlaceholder = text: 
    builtins.isString text && 
    (lib.hasInfix "\${config.sops.placeholder." text);

  # Use a different approach: collect the information we need during evaluation
  # but defer all file operations to the activation script
  homeFiles = config.home.file or {};
  
  # Extract files with placeholders without creating circular dependency
  filesWithPlaceholdersInfo = lib.foldl'
    (acc: fileName:
      let
        fileConfig = homeFiles.${fileName} or {};
        hasPlaceholders = fileConfig ? text && hasSopsPlaceholder fileConfig.text;
      in
        if hasPlaceholders then
          acc // {
            ${fileName} = {
              content = fileConfig.text;
              templateName = "hm-${builtins.replaceStrings ["/"] ["-"] fileName}";
            };
          }
        else acc
    )
    {}
    (builtins.attrNames homeFiles);

  # Generate SOPS templates for the NixOS module
  sopsTemplates = lib.mapAttrs
    (fileName: info: {
      content = info.content;
      owner = config.home.username;
      group = "users";
    })
    filesWithPlaceholdersInfo;

  # Generate activation script to handle both disabling original files and linking templates
  activationScript = lib.optionalString (filesWithPlaceholdersInfo != {}) ''
    echo "🔗 Sopswarden: managing Home Manager SOPS templates..."
    
    # Remove original files with placeholders to avoid conflicts
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList
      (fileName: info: ''
        target_file="${config.home.homeDirectory}/${fileName}"
        if [[ -f "$target_file" && ! -L "$target_file" ]]; then
          echo "  🗑️  Removing original file with placeholders: ${fileName}"
          rm -f "$target_file"
        fi
      '')
      filesWithPlaceholdersInfo
    )}
    
    # Link SOPS templates to their final locations
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList
      (fileName: info: ''
        target_path="${config.home.homeDirectory}/${fileName}"
        template_path="/run/secrets/${info.templateName}"
        
        if [[ -f "$template_path" ]]; then
          mkdir -p "$(dirname "$target_path")"
          ln -sf "$template_path" "$target_path"
          echo "  ✓ ${fileName} -> $template_path"
        else
          echo "  ⚠️  Template not found: $template_path"
        fi
      '')
      filesWithPlaceholdersInfo
    )}
    
    echo "✅ Sopswarden: Home Manager template linking complete"
  '';

in {
  # Export SOPS templates to be used by the NixOS SOPS configuration
  _module.args.sopswarden-hm-templates = sopsTemplates;

  # Add activation script to manage templates (no file modification here)
  home.activation.sopswarden-template-linking = lib.hm.dag.entryAfter ["writeBoundary"] activationScript;

  # Provide informative warnings
  warnings = lib.optional (filesWithPlaceholdersInfo != {}) 
    "sopswarden: Detected ${toString (builtins.length (builtins.attrNames filesWithPlaceholdersInfo))} Home Manager files with SOPS placeholders: ${lib.concatStringsSep ", " (builtins.attrNames filesWithPlaceholdersInfo)}. Templates will be generated and linked automatically.";
}
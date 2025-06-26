# Home Manager SOPS template integration
# Automatically detects Home Manager files with SOPS placeholders and converts them to templates

{ lib, config, ... }:

let
  # Helper to detect if a string contains SOPS placeholders
  hasSopsPlaceholder = text: 
    builtins.isString text && 
    (lib.hasInfix "\${config.sops.placeholder." text);
  
  # Find all Home Manager files that contain SOPS placeholders
  homeFiles = config.home.file or {};
  filesWithPlaceholders = lib.filterAttrs 
    (name: fileConfig: 
      fileConfig ? text && hasSopsPlaceholder fileConfig.text
    ) 
    homeFiles;
  
  # Generate SOPS templates for files with placeholders
  # Each template will be resolved by SOPS-nix at activation time
  sopsTemplates = lib.mapAttrs
    (fileName: fileConfig: {
      content = fileConfig.text;
      # SOPS will place the rendered file at /run/sops-templates/${fileName}
      # and resolve all ${config.sops.placeholder.*} references
    })
    filesWithPlaceholders;
  
  # Create Home Manager activation script to link rendered templates
  # This runs after SOPS has resolved all placeholders
  templateActivation = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    echo "🔄 Sopswarden: linking SOPS-rendered template files..."
    
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (fileName: fileConfig: 
      let
        # Determine target path for the file
        targetPath = if fileConfig ? target 
                    then fileConfig.target 
                    else "$HOME/${fileName}";
        # SOPS template path (where SOPS-nix places the resolved file)
        templatePath = "/run/sops-templates/${fileName}";
      in ''
        if [ -f "${templatePath}" ]; then
          echo "  📝 Linking ${fileName} → ${targetPath}"
          mkdir -p "$(dirname "${targetPath}")"
          # Remove any existing symlink/file and replace with template link
          rm -f "${targetPath}"
          ln -sf "${templatePath}" "${targetPath}"
        else
          echo "  ⚠️  Template not found: ${templatePath}"
          echo "     Make sure SOPS secrets are properly configured"
        fi
      ''
    ) filesWithPlaceholders)}
    
    echo "✅ Sopswarden: template linking complete (${toString (builtins.length (builtins.attrNames filesWithPlaceholders))} files)"
  '';

in {
  # Automatically generate SOPS templates for Home Manager files with placeholders
  sops.templates = sopsTemplates;
  
  # Override Home Manager files with placeholders to prevent them from being linked
  # We'll handle the linking ourselves via the activation script
  home.file = lib.mapAttrs
    (fileName: fileConfig:
      if filesWithPlaceholders ? ${fileName}
      then fileConfig // {
        # Disable the original file generation for files with placeholders
        # Our activation script will handle linking the resolved templates
        enable = false;
      }
      else fileConfig
    )
    homeFiles;
  
  # Add activation script to link SOPS-resolved templates
  home.activation.sopswarden-templates = 
    if filesWithPlaceholders != {}
    then templateActivation
    else lib.hm.dag.entryAnywhere "echo 'Sopswarden: no template files to process'";
  
  # Informational warnings
  warnings = lib.optional (filesWithPlaceholders != {}) 
    "sopswarden: Processing ${toString (builtins.length (builtins.attrNames filesWithPlaceholders))} Home Manager files with SOPS placeholders: ${lib.concatStringsSep ", " (builtins.attrNames filesWithPlaceholders)}";
}
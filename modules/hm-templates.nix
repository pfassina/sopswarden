# Home Manager SOPS template integration
# Automatically detects Home Manager files with SOPS placeholders and converts them to templates

{ lib, config, ... }:

let
  # Helper to detect if a string contains SOPS placeholders
  hasSopsPlaceholder = text: 
    builtins.isString text && 
    (lib.hasInfix "\${config.sops.placeholder." text);

in {
  # This is a simplified version that just detects SOPS placeholders
  # The full template integration requires more careful design to avoid infinite recursion
  
  # For now, just provide a warning when SOPS placeholders are detected
  warnings = 
    let
      homeFiles = config.home.file or {};
      filesWithPlaceholders = lib.filterAttrs 
        (name: fileConfig: 
          fileConfig ? text && hasSopsPlaceholder fileConfig.text
        ) 
        homeFiles;
    in
      lib.optional (filesWithPlaceholders != {}) 
        "sopswarden: Detected ${toString (builtins.length (builtins.attrNames filesWithPlaceholders))} Home Manager files with SOPS placeholders: ${lib.concatStringsSep ", " (builtins.attrNames filesWithPlaceholders)}. Full template integration coming soon.";
}
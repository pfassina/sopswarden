# Home Manager SOPS template integration
# Detects Home Manager files with SOPS placeholders and declares them as templates

{ lib, config, ... }:

let
  # Helper to detect if a string contains SOPS placeholders
  hasSopsPlaceholder = text: 
    builtins.isString text && 
    (lib.hasInfix "\${config.sops.placeholder." text);

  # Keep SOPS placeholder format as-is (sops-nix handles substitution directly)
  keepSopsPlaceholders = text: text;

  # Collect files with SOPS placeholders from home.file
  homeFiles = config.home.file or {};
  
  # Extract files with placeholders and convert them to Go template format
  filesWithPlaceholdersInfo = lib.foldl'
    (acc: fileName:
      let
        fileConfig = homeFiles.${fileName} or {};
        hasPlaceholders = fileConfig ? text && hasSopsPlaceholder fileConfig.text;
      in
        if hasPlaceholders then
          acc // {
            ${fileName} = {
              content = keepSopsPlaceholders fileConfig.text;
              owner = config.home.username;
              group = "users";
              mode = "0600";
            };
          }
        else acc
    )
    {}
    (builtins.attrNames homeFiles);

in {
  imports = [
    ./shared.nix
  ];

  config = {
    # Export templates for the NixOS SOPS module to process
    sopswarden.hmTemplates = filesWithPlaceholdersInfo;

    # Automatically disable Home Manager files that contain SOPS placeholders
    # This prevents conflicts between HM symlinks and SOPS-generated files
    # Using mkForce null for compatibility with all Home Manager versions
    home.file = lib.mapAttrs (_: _: lib.mkForce null) filesWithPlaceholdersInfo;

    # Provide informative warnings
    warnings = lib.optional (filesWithPlaceholdersInfo != {}) 
      "sopswarden: Detected ${toString (builtins.length (builtins.attrNames filesWithPlaceholdersInfo))} Home Manager files with SOPS placeholders: ${lib.concatStringsSep ", " (builtins.attrNames filesWithPlaceholdersInfo)}. Templates will be processed by SOPS during system activation. Home Manager symlinks disabled automatically via mkForce null.";
  };

  # Note: Template processing now handled by NixOS module as root
  # Files will be written directly to final locations by SOPS
}
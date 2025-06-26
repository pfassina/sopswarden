# Template detection module - detects HM files with SOPS placeholders
# Uses deferred evaluation to avoid circular dependencies

{ lib, config, ... }:

let
  # Helper to detect if a string contains SOPS placeholders
  hasSopsPlaceholder = text: 
    builtins.isString text && 
    (lib.hasInfix "\${config.sops.placeholder." text);

in {
  imports = [
    ./shared.nix
  ];

  options.sopswarden.detectedFiles = lib.mkOption {
    type = with lib.types; attrsOf anything;
    internal = true;
    # Use a function to defer evaluation and avoid recursion
    default = {};
    description = "Files produced by HM that contain SOPS placeholders";
  };

  # Use config section to set the detected files after home.file is stable
  config.sopswarden.detectedFiles = lib.mkDefault (
    let
      # Read home.file but do it in a way that doesn't create circular deps
      # The key is to read only the non-sopswarden parts
      homeFiles = lib.filterAttrs (name: _: 
        # Skip any files that might be set by sopswarden modules
        !(lib.hasPrefix "sopswarden-" name)
      ) (config.home.file or {});
      
      # Extract files with SOPS placeholders and convert to template format
      filesWithPlaceholders = lib.filterAttrs
        (fileName: fileConfig:
          fileConfig ? text && hasSopsPlaceholder fileConfig.text
        )
        homeFiles;

      # Convert to template format for SOPS
      templatesInfo = lib.mapAttrs
        (fileName: fileConfig: {
          content = fileConfig.text;
          owner = config.home.username;
          group = "users";
          mode = "0600";
        })
        filesWithPlaceholders;

    in templatesInfo
  );

  # Export for NixOS module consumption
  config.sopswarden.hmTemplates = config.sopswarden.detectedFiles;
}
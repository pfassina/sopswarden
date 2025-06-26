# Home Manager SOPS template integration
# Detects Home Manager files with SOPS placeholders and declares them as templates

{ lib, config, ... }:

let
  # Helper to detect if a string contains SOPS placeholders
  hasSopsPlaceholder = text: 
    builtins.isString text && 
    (lib.hasInfix "\${config.sops.placeholder." text);

  # Helper to convert SOPS placeholders to Go template format
  convertToGoTemplate = text:
    # Convert ${config.sops.placeholder.secret-name} to {{ .secret_name }}
    let
      # First replace hyphens with underscores in secret names
      step1 = builtins.replaceStrings ["-"] ["_"] text;
      # Then replace the placeholder format
      step2 = builtins.replaceStrings ["\${config.sops.placeholder."] ["{{ ."] step1;
      # Finally close the template syntax
      step3 = builtins.replaceStrings ["}"] [" }}"] step2;
    in step3;

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
              content = convertToGoTemplate fileConfig.text;
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

  # Export templates for the NixOS SOPS module to process
  sopswarden.hmTemplates = filesWithPlaceholdersInfo;

  # Note: We don't modify home.file here to avoid circular dependencies.
  # Instead, we rely on SOPS templates taking precedence by writing directly to the final paths.

  # Provide informative warnings
  warnings = lib.optional (filesWithPlaceholdersInfo != {}) 
    "sopswarden: Detected ${toString (builtins.length (builtins.attrNames filesWithPlaceholdersInfo))} Home Manager files with SOPS placeholders: ${lib.concatStringsSep ", " (builtins.attrNames filesWithPlaceholdersInfo)}. Templates will be rendered directly by SOPS.";
}
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

  # Use Home Manager activation to replace placeholder files with processed templates
  home.activation.sopswarden-template-processing = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "🔄 Sopswarden: processing Home Manager SOPS templates..."
    
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList
      (fileName: info: ''
        target_path="${config.home.homeDirectory}/${fileName}"
        
        echo "  📝 Processing ${fileName}"
        
        # Remove Home Manager symlink if it exists
        if [[ -L "$target_path" ]]; then
          echo "    🗑️  Removing Home Manager symlink"
          rm -f "$target_path"
        fi
        
        # Create a temporary template file with Go template content
        temp_template=$(mktemp)
        cat > "$temp_template" << 'EOF'
${info.content}
EOF
        
        # Find all available secrets and substitute them
        for secret_file in /run/secrets/*; do
          if [[ -f "$secret_file" ]]; then
            secret_name=$(basename "$secret_file")
            secret_value=$(cat "$secret_file")
            # Convert secret name from git-username to git_username for template matching
            template_name=''${secret_name//-/_}
            
            echo "    🔍 Checking secret: $secret_name -> template var: {{ .$template_name }}"
            
            # Replace the template variable for this secret
            if grep -q "{{ \.$template_name }}" "$temp_template"; then
              echo "    ✓ Substituting {{ .$template_name }} with secret value"
              sed -i "s|{{ \.$template_name }}|$secret_value|g" "$temp_template"
            fi
          fi
        done
        
        # Install the processed template
        mkdir -p "$(dirname "$target_path")"
        cp "$temp_template" "$target_path"
        chmod ${info.mode} "$target_path"
        chown ${info.owner}:${info.group} "$target_path" 2>/dev/null || true
        rm -f "$temp_template"
        
        echo "    ✓ Installed processed template to ${fileName}"
      '')
      filesWithPlaceholdersInfo
    )}
    
    echo "✅ Sopswarden: Home Manager template processing complete"
  '';

  # Provide informative warnings
  warnings = lib.optional (filesWithPlaceholdersInfo != {}) 
    "sopswarden: Detected ${toString (builtins.length (builtins.attrNames filesWithPlaceholdersInfo))} Home Manager files with SOPS placeholders: ${lib.concatStringsSep ", " (builtins.attrNames filesWithPlaceholdersInfo)}. Templates will be processed during Home Manager activation.";
}
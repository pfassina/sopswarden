# Home Manager Secrets Integration Investigation

## Overview

This document outlines questions and technical details that need investigation to determine how sopsWarden secrets can be properly integrated with Home Manager configurations, both in standalone and NixOS module contexts.

## Core Questions to Investigate

### 1. Module Argument Flow
- How exactly do `_module.args` flow from NixOS to Home Manager when Home Manager is used as a NixOS module?
- Does Home Manager create its own isolated module evaluation context even when running as a NixOS module?
- What is the precise mechanism by which arguments are passed between these contexts?

### 2. Home Manager Module Evaluation
- When Home Manager runs as `home-manager.nixosModules.home-manager`, does it inherit the parent NixOS module's `_module.args`?
- How does the `osConfig` argument work, and what exactly does it contain?
- Can `_module.args` be set within `home-manager.users.<user>` configurations?

### 3. Standalone vs NixOS Module Behavior
- What are the fundamental differences in argument passing between:
  - `home-manager.lib.homeManagerConfiguration` (standalone)
  - `home-manager.nixosModules.home-manager` (NixOS module)
- How do `specialArgs` and `extraSpecialArgs` work in each context?

### 4. sopsWarden Integration Patterns
- Can the current sopsWarden `secrets.*` pattern work in Home Manager contexts?
- What modifications would be needed to the existing sopsWarden modules to support Home Manager?
- Should secrets be passed via `_module.args`, `osConfig`, or a different mechanism?

## Technical Details for Investigation

### Current sopsWarden NixOS Module Behavior
From `/home/mead/Code/sopswarden/modules/nixos.nix` lines 155-158:
```nix
# Export secrets for easy access in other modules
_module.args = { 
  secrets = secretAccessors;
  sopswardenSecrets = secretAccessors; # Alternative name
};
```

This makes `secrets` available to all NixOS modules via the module system's argument passing.

### Current sopsWarden Home Manager Module
From `/home/mead/Code/sopswarden/modules/home-manager.nix`:
- Does not export any `_module.args`
- Only provides sync script functionality
- No integration with SOPS or secret accessors
- Much simpler implementation focused on user-level secret syncing

### Secret Accessor Implementation
From `/home/mead/Code/sopswarden/lib/default.nix` lines 89-95:
```nix
mkSecretAccessors = { config, secrets }:
  builtins.mapAttrs (name: _:
    # Always return the SOPS secret path - never read content at evaluation time
    # This keeps evaluation pure and defers all file access to runtime
    config.sops.secrets.${name}.path
  ) secrets;
```

The accessors return paths like `/run/secrets/secret-name` that reference SOPS-managed secrets.

### Advanced Example Home Manager Usage
From `/home/mead/Code/sopswarden/examples/advanced/flake.nix` lines 131-146:
```nix
# Home manager integration
home-manager.users.myuser = {
  home.stateVersion = "24.11";
  # Configure rbw for the user
  programs.rbw = {
    enable = true;
    settings = {
      email = "admin@company.com";
      base_url = "https://vault.company.com";  # Self-hosted Bitwarden
      lock_timeout = 3600;
      pinentry = pkgs.pinentry-gtk2;
    };
  };
  
  # Note: programs.sopswarden would be available if homeManagerModules were imported
  # For now, sopswarden is configured at system level
};
```

Note: The example does NOT use `secrets.*` in the Home Manager configuration.

## Research Areas

### 1. Module System Documentation
- NixOS manual sections on module arguments and `_module.args`
- Home Manager manual sections on module integration
- Source code analysis of both module systems

### 2. Argument Passing Mechanisms
Investigation needed on:
- `_module.args` vs `specialArgs` vs `extraSpecialArgs`
- Submodule argument inheritance rules
- Cross-module-system argument passing

### 3. SOPS Integration Patterns
- How other SOPS-based tools handle Home Manager integration
- Whether SOPS secrets can be shared between NixOS and Home Manager contexts
- File permission and ownership considerations for user vs system secrets

### 4. Practical Testing Required
Test scenarios to implement:
- NixOS module with Home Manager module using `secrets.*` syntax
- Standalone Home Manager with sopsWarden integration
- Different methods of passing secrets to Home Manager contexts
- Error behaviors and edge cases

## Current Limitations and Constraints

### Known Issues
1. Home Manager submodules don't inherit arguments from parent modules by default
2. SOPS integration may have permission issues in user contexts
3. The current sopsWarden Home Manager module is minimal and lacks secret accessor functionality

### Architecture Considerations
- Pure evaluation requirements must be maintained
- Secret paths vs secret content access patterns
- User vs system secret management boundaries
- Integration with existing Home Manager workflows

## Investigation Methodology

### Code Analysis
1. Examine Home Manager source code for argument passing mechanisms
2. Trace `_module.args` flow in both standalone and NixOS module contexts
3. Analyze existing SOPS integrations in the Home Manager ecosystem

### Practical Testing
1. Create test configurations for each integration pattern
2. Validate argument availability in different contexts
3. Test error cases and edge behaviors
4. Measure performance and evaluation impacts

### Community Research
1. Survey existing Home Manager + SOPS integration patterns
2. Review relevant GitHub issues and discussions
3. Examine similar tools and their approaches

## Expected Outcomes

This investigation should result in:
1. Clear documentation of argument flow mechanisms
2. Recommended integration patterns for different use cases
3. Potential module enhancements to support Home Manager properly
4. Updated examples demonstrating working configurations
5. Clear guidelines on when to use each integration approach

## Implementation Considerations

Based on investigation results, potential implementation paths include:
1. Enhanced Home Manager module with `_module.args` export
2. Alternative secret passing mechanisms via `osConfig`
3. Hybrid approach supporting both standalone and NixOS module contexts
4. Documentation updates for proper usage patterns

---

*This investigation should be completed before implementing Home Manager secrets integration to ensure the chosen approach is robust and follows NixOS/Home Manager best practices.*
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

sopsWarden is a Nix flake that integrates SOPS secrets management with Bitwarden for NixOS systems. It automatically syncs secrets from Bitwarden vaults to encrypted SOPS files, eliminating manual secret management.

**Core Goal:** Make it trivially easy to both define and use secrets in NixOS configurations. The key feature is seamless secret access via `pwd = secrets.pwd;` syntax - this ergonomic API must be preserved in all changes.

## Development Commands

### Testing
```bash
# Run full test suite
./tests/run-tests.sh

# Individual test types
nix flake check --no-build                    # Flake validation
nix-build tests/unit/test-lib.nix             # Unit tests
nix build .#sopswarden-sync                   # Package build
nix flake check examples/basic                # Example validation
```

### Development Shell
```bash
nix develop                                    # Enter dev shell with all tools
```

### Code Quality
```bash
nixpkgs-fmt .                                  # Format Nix code
statix check .                                # Static analysis
deadnix .                                     # Dead code detection
```

## Architecture

### Core Components

**Flake Structure:**
- `flake.nix` - Main flake definition, exports modules and packages
- `lib/default.nix` - Core library functions for script generation and secret management
- `lib/sync-script.nix` - Bash script template for the sopswarden-sync command
- `modules/nixos.nix` - NixOS module with full SOPS integration
- `modules/home-manager.nix` - Home Manager module for user-level usage

**Key Functions:**
- `mkSyncScript` - Generates parameterized sopswarden-sync bash script with embedded secrets
- `mkSopsSecrets` - Creates SOPS secret configuration from user definitions
- `mkSecretAccessors` - **CRITICAL**: Provides runtime access to decrypted secrets via `secrets.secret-name` syntax
- `normalizeSecretDef` - Normalizes secret definitions to standard format

### Secret Access Pattern (Core Feature)

The primary value proposition is the ergonomic secret access pattern:

```nix
# User defines secrets
services.sopswarden.secrets = {
  wifi-password = "Home WiFi";
  api-key = { name = "My Service"; user = "admin@example.com"; };
};

# Later in config, secrets are accessible as simple attributes
services.someservice.password = secrets.wifi-password;
networking.wireless.networks."MyWiFi".psk = secrets.wifi-password;
services.api.key = secrets.api-key;
```

This is implemented by `mkSecretAccessors` in `lib/default.nix:90-102`, which:
1. Maps secret names to their SOPS paths
2. Attempts to read decrypted content when `--impure` is used
3. Falls back to file paths when content cannot be read
4. Exports the resulting attribute set via `_module.args.secrets`

### Script Generation Flow

The sync script is generated at build time using Nix string interpolation in `lib/sync-script.nix`. The script:

1. **Configuration Setup** - Sets up paths and working directory
2. **Embedded Secret Processing** - Secret definitions embedded directly in generated script (eliminates bootstrap issues)
3. **Bitwarden Access** - Fetches secrets using rbw CLI with graceful error handling
4. **Graceful Degradation** - Missing secrets produce warnings, not failures
5. **SOPS Encryption** - Creates temporary YAML file and encrypts with age keys
6. **Success Reporting** - Reports successful/failed secret counts

### Nix Store Compatibility

The script includes comprehensive compatibility for Nix flake environments where configuration files are in read-only Nix store paths:

**Working Directory Detection:**
- Detects when `SECRETS_FILE` is a Nix store path (`/nix/store/*`)
- Auto-discovers actual config directory by searching for `flake.nix`, `configuration.nix`, or `secrets` directory
- Falls back to common locations: `$HOME/nix`, `$HOME/.config/nixos`, `$HOME/nixos`

**Output Path Handling:**
- Detects when `SOPS_FILE` is a Nix store path
- Strips Nix store hash prefix using `${filename#*-}` expansion
- Redirects output to writable runtime directory with clean filename

**Temporary File Management:**
- Uses system temporary directory (`mktemp -d`) instead of Nix store paths
- Copies `.sops.yaml` config to temp directory for encryption context
- Explicitly specifies config with `sops --config .sops.yaml --encrypt`
- Proper cleanup with `trap` for temporary files

This ensures the script works seamlessly in both traditional filesystem and Nix store environments without requiring user configuration changes.

### Module Integration

**NixOS Module (`modules/nixos.nix`):**
- Imports sops-nix module
- Accepts secret definitions directly via `services.sopswarden.secrets` option
- Configures SOPS with user secrets
- **Exports secret accessors to other modules via `_module.args.secrets`**
- Generates sync script with embedded secret definitions (eliminates bootstrap issues)
- Provides warnings for missing secrets file
- Installs packages and sync command system-wide

**Home Manager Module (`modules/home-manager.nix`):**
- Simplified version for user-level secret management
- Installs packages in user profile
- No SOPS integration (user must handle separately)

### Secret Definition System

Users define secrets directly in NixOS configuration in two formats:
- **Simple:** `secretName = "Bitwarden Item Name"`
- **Complex:** `secretName = { name = "Item"; user = "email"; type = "note"; field = "custom"; }`

Example:
```nix
services.sopswarden.secrets = {
  wifi-password = "Home WiFi";  # Simple
  api-key = { name = "API"; user = "admin"; };  # Complex
};
```

The `normalizeSecretDef` function converts simple definitions to the complex format internally.

### File Organization

- `examples/` - Working example configurations (basic, advanced, migration)
- `tests/` - Comprehensive test suite (unit, integration, nixos module tests)
- `docs/` - Additional documentation

## Dependencies

**Runtime Dependencies:**
- `rbw` - Bitwarden CLI client
- `sops` - Secret encryption/decryption
- `age` - Encryption backend

**Development Dependencies:**
- `nixpkgs-fmt` - Nix code formatting
- `statix` - Static analysis
- `deadnix` - Dead code detection

## Common Patterns

### Working with Generated Scripts
The sync script is generated at build time, so changes to `lib/sync-script.nix` require rebuilding the package. Test changes with:
```bash
nix build .#sopswarden-sync
./result/bin/sopswarden-sync
```

### Adding New Library Functions
Add to `lib/default.nix` and export in the `rec` block. Functions should be pure and parameterized for reuse across NixOS and Home Manager modules.

### Preserving Secret Access API
When making changes, always ensure the `secrets.secret-name` access pattern continues to work. This is the core value proposition and must never be broken. Test with:
```nix
# In a test configuration
services.sopswarden.secrets.test-secret = "Test Item";
# Later...
environment.variables.TEST = secrets.test-secret;  # This must work
```

### Testing Integration
Integration tests require mock Bitwarden data. Use the test framework in `tests/integration/` that provides controlled test scenarios.

## Critical Implementation Details

### Secret Accessor Export
The NixOS module exports secrets via `_module.args` (line 169 in `modules/nixos.nix`):
```nix
_module.args = { 
  secrets = secretAccessors;
  sopswardenSecrets = secretAccessors; # Alternative name
};
```

This makes `secrets` available as a function argument in all other modules in the same configuration.

### Content-First Strategy
The `mkSecretAccessors` function implements a "content-first" strategy:
- Try to read actual secret content when possible (requires `--impure`)
- Fall back to file paths when content reading fails
- This enables both immediate use and lazy evaluation patterns
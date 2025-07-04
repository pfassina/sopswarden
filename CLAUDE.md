# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

sopsWarden is a Nix flake that integrates SOPS secrets management with Bitwarden for NixOS systems. It automatically syncs secrets from Bitwarden vaults to encrypted SOPS files, eliminating manual secret management.

**Core Goal:** Make it trivially easy to both define and use secrets in NixOS configurations. The key feature is seamless secret access via `secrets.secret-name` syntax - this ergonomic API must be preserved in all changes.

## Development Commands

### Testing

**ALWAYS run tests after making changes to the flake:**

```bash
# Full test suite (REQUIRED after flake changes)
./tests/run-tests.sh

# Quick validation during development
nix flake check --no-build                    # Flake validation  
nix build .#sopswarden-sync                   # Package build
nix-build tests/core/test-pure-evaluation.nix # Core functionality check
```

**Core test categories:**
```bash
# Core functionality (impure evaluation, library functions)
nix-build tests/core/test-pure-evaluation.nix
nix-build tests/core/test-lib-functions.nix

# NixOS module integration (secrets.secret-name syntax)
nix-build tests/modules/test-nixos-module.nix

# User workflows (fresh install, adding secrets)
nix-build tests/workflows/test-fresh-install.nix
nix-build tests/workflows/test-add-secrets.nix

# Runtime integration (sync script generation)
nix-build tests/integration/test-runtime-sync.nix
```

**After any changes to core functionality:**
- Run `./tests/run-tests.sh` to ensure all tests pass
- Pay special attention to workflow tests - they validate the user experience
- The test suite must show "✅ Tests passed: 11/11" for the PR to be acceptable

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
- `mkSyncScript` - Generates parameterized sopswarden-sync bash script using `nix eval --impure`
- `mkSopsSecrets` - Creates SOPS secret configuration from user definitions
- `mkSecretAccessors` - **CRITICAL**: Provides access to secrets via `secrets.secret-name` syntax using impure evaluation
- `mkHashTracker` - Hash-based change detection using impure file reads
- `normalizeSecretDef` - Normalizes secret definitions to standard format

**Impure Evaluation Architecture:**
- **Uses `--impure` by Design**: Intentionally reads files during evaluation for secret access
- **Direct File Access**: `builtins.readFile` and `builtins.pathExists` used in `mkSecretAccessors`
- **Runtime Sync**: sopswarden-sync script handles Bitwarden integration and SOPS encryption
- **Change Detection**: Hash tracking prevents unnecessary re-encryption

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

This is implemented by `mkSecretAccessors` which attempts to read secret files during evaluation using `builtins.readFile`, falling back to SOPS paths when files don't exist, and exports them via `_module.args.secrets`.

### Sync Script Architecture

The impure evaluation architecture uses the sopswarden-sync script for secret management:

1. **sopswarden-sync** - Bash script that uses `nix eval --impure` to read secrets configuration
2. **Bitwarden Integration** - Fetches secrets from Bitwarden using `rbw` CLI
3. **SOPS Encryption** - Encrypts secrets using SOPS with age keys
4. **Hash Tracking** - Prevents unnecessary re-encryption using change detection

This design requires `--impure` flags but provides direct access to secret values during evaluation.

### Module Integration

**NixOS Module:** 
- Accepts secret definitions via `services.sopswarden.secrets`
- Configures SOPS integration with sops-nix
- Exports secret accessors via `_module.args.secrets` using impure evaluation
- Includes systemd service for running sopswarden-sync

**Home Manager Module:** 
- Simplified version for user-level usage
- No SOPS integration

## Dependencies

**Runtime:** `rbw`, `sops`, `age`  
**Development:** `nixpkgs-fmt`, `statix`, `deadnix`

## Critical Implementation Details

### Impure Evaluation Design
- **Uses `builtins.readFile` by Design**: `mkSecretAccessors` reads secret files during evaluation
- **Smart Fallback**: Returns actual secret values when available, SOPS paths when not
- **Hash-based Change Detection**: Uses `mkHashTracker` to prevent unnecessary operations
- **Requires `--impure` Flag**: Sync script explicitly uses `nix eval --impure`

### Secret Accessor Export
The NixOS module exports secrets via `_module.args.secrets`, making them available to all other modules.

### Preserving API Compatibility
Always ensure the `secrets.secret-name` access pattern continues to work - this is the core value proposition.

### Testing Requirements
The comprehensive test suite (`./tests/run-tests.sh`) validates:

**Core Functionality:**
- Impure evaluation with `--impure` flags as expected
- All library functions with edge cases
- SOPS configuration generation
- Secret accessor value reading and path fallback

**User Experience:**
- Fresh installation workflow: user adds sopswarden → defines secrets → uses in services
- Add secrets workflow: user adds new secrets → existing services unaffected → new services work
- Real NixOS service integration: `secrets.wifi-password` works in `networking.wireless.networks`

**Critical API Validation:**
- `secrets.secret-name` syntax works in all NixOS modules
- Different secret types (simple, complex, note) all work
- Sync script handles Bitwarden integration and SOPS encryption
- Hash-based change detection prevents unnecessary operations

**When to run tests:**
- **ALWAYS** after changing any file in `lib/`, `modules/`, or `flake.nix`
- Before creating PRs or commits
- When adding new features or fixing bugs
- The test result must be "✅ Tests passed: 11/11"
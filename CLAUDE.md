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
# Core functionality (pure evaluation, library functions)
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
- `mkSyncScript` - Generates parameterized sopswarden-sync bash script with embedded secrets
- `mkSopsSecrets` - Creates SOPS secret configuration from user definitions
- `mkSecretAccessors` - **CRITICAL**: Provides runtime access to decrypted secrets via `secrets.secret-name` syntax
- `normalizeSecretDef` - Normalizes secret definitions to standard format

**Pure Evaluation Architecture (2025-06-22):**
- **No `--impure` Required**: Never reads files during evaluation 
- **No Bootstrap Mode**: Runtime validation eliminates circular dependencies
- **String Paths**: Uses `types.str` to avoid Nix store caching issues
- **Runtime Validation**: systemd services handle secret sync and validation

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

This is implemented by `mkSecretAccessors` which maps secret names to their SOPS paths and exports them via `_module.args.secrets`.

### Runtime Validation Architecture

The pure evaluation architecture uses systemd services for all secret management:

1. **sopswarden-sync.service** - Fetches secrets from Bitwarden and encrypts them
2. **sopswarden-validate.service** - Validates SOPS file after sync  
3. Both run before `sysinit.target` to ensure secrets are ready before other services

This eliminates the need for `--impure` flags or bootstrap modes.

### Module Integration

**NixOS Module:** 
- Accepts secret definitions via `services.sopswarden.secrets`
- Configures SOPS and systemd services
- Exports secret accessors via `_module.args.secrets`

**Home Manager Module:** 
- Simplified version for user-level usage
- No SOPS integration

## Dependencies

**Runtime:** `rbw`, `sops`, `age`  
**Development:** `nixpkgs-fmt`, `statix`, `deadnix`

## Critical Implementation Details

### Pure Evaluation Requirements
- **Never** use `builtins.readFile` during evaluation
- **Always** return SOPS paths from `mkSecretAccessors` 
- **Use** string paths (`types.str`) to avoid Nix store caching
- **Defer** all file operations to runtime via systemd services

### Secret Accessor Export
The NixOS module exports secrets via `_module.args.secrets`, making them available to all other modules.

### Preserving API Compatibility
Always ensure the `secrets.secret-name` access pattern continues to work - this is the core value proposition.

### Testing Requirements
The comprehensive test suite (`./tests/run-tests.sh`) validates:

**Core Functionality:**
- Pure evaluation without `--impure` flags
- All library functions with edge cases
- SOPS configuration generation
- Secret accessor path mapping

**User Experience:**
- Fresh installation workflow: user adds sopswarden → defines secrets → uses in services
- Add secrets workflow: user adds new secrets → existing services unaffected → new services work
- Real NixOS service integration: `secrets.wifi-password` works in `networking.wireless.networks`

**Critical API Validation:**
- `secrets.secret-name` syntax works in all NixOS modules
- Different secret types (simple, complex, note) all work
- Runtime systemd services handle sync and validation
- No manual intervention required anywhere

**When to run tests:**
- **ALWAYS** after changing any file in `lib/`, `modules/`, or `flake.nix`
- Before creating PRs or commits
- When adding new features or fixing bugs
- The test result must be "✅ Tests passed: 11/11"
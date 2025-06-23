# Sopswarden Test Suite

Comprehensive test framework validating sopswarden's pure evaluation architecture and user workflows.

## Quick Start

```bash
# Run full test suite
./tests/run-tests.sh

# Quick validation
nix flake check --no-build
```

## Test Structure

```
tests/
├── core/                           # Core functionality
│   ├── test-pure-evaluation.nix    # Pure evaluation validation
│   └── test-lib-functions.nix      # Library function testing
├── modules/                        # NixOS integration
│   └── test-nixos-module.nix       # Module functionality
├── workflows/                      # User workflows
│   ├── test-fresh-install.nix      # Fresh installation
│   └── test-add-secrets.nix        # Adding secrets
├── integration/                    # Runtime integration
│   └── test-runtime-sync.nix       # Sync script testing
├── unit/                          # Legacy tests
│   └── test-lib.nix               # Backward compatibility (skipped)
└── run-tests.sh                   # Test runner
```

## Test Categories

### 🔧 Core Functionality
- **Pure Evaluation** - Verifies no `--impure` flags needed
- **Library Functions** - All core functions with edge cases

### 📦 NixOS Module Integration  
- **Secret Accessors** - `secrets.secret-name` → `/run/secrets/secret-name`
- **SOPS Integration** - Automatic SOPS configuration generation
- **Service Integration** - Usage in real NixOS services

### 🔄 User Workflows
- **Fresh Install** - Complete installation from scratch
- **Add Secrets** - Adding secrets to existing configuration
- **Service Usage** - Secrets in PostgreSQL, Nginx, systemd, etc.

### 🔗 Runtime Integration
- **Sync Script** - sopswarden-sync generation and testing
- **Mock Bitwarden** - Integration without real vault access

## Running Tests

### Individual Tests
```bash
# Core tests
nix-build tests/core/test-pure-evaluation.nix
nix-build tests/core/test-lib-functions.nix

# Module tests  
nix-build tests/modules/test-nixos-module.nix

# Workflow tests
nix-build tests/workflows/test-fresh-install.nix
nix-build tests/workflows/test-add-secrets.nix

# Integration tests
nix-build tests/integration/test-runtime-sync.nix
```

### Development Workflow
```bash
# After making changes to the flake
./tests/run-tests.sh

# Quick validation during development
nix flake check --no-build
nix-build tests/core/test-pure-evaluation.nix
```

## Key Features Tested

### ✅ Core Value Proposition
- **secrets.secret-name syntax** - Works in all NixOS services
- **Pure evaluation** - No `--impure` flags anywhere
- **Zero configuration** - Just add secrets and use them
- **Runtime automation** - systemd handles sync/validation

### ✅ Secret Types
- **Simple** - `secret-name = "Bitwarden Item"`
- **Complex** - `secret-name = { name = "Item"; user = "user@example.com"; }`
- **Note** - `secret-name = { name = "Note"; type = "note"; field = "field"; }`

### ✅ NixOS Integration
- **Wireless** - `networking.wireless.networks.MyWiFi.psk = secrets.wifi-password`
- **PostgreSQL** - `services.postgresql.passwordFile = secrets.db-password`
- **Nginx** - `services.nginx.virtualHosts."site".sslCertificate = secrets.ssl-cert`
- **Environment** - `environment.variables.API_KEY = secrets.api-key`
- **Systemd** - `systemd.services.app.serviceConfig.EnvironmentFile = secrets.config`

### ✅ Runtime Features
- **Systemd Services** - sopswarden-sync, sopswarden-validate
- **SOPS Integration** - Automatic encryption/decryption
- **Error Handling** - Graceful failures and validation

## Test Results

The test suite validates:

```
✅ Tests passed: 11/11
   🔧 Core functionality (2/2)
   📦 Module integration (1/1) 
   🔄 User workflows (2/2)
   🔗 Integration tests (1/1)
   📦 Flake & packages (2/2)
   📚 Examples (2/2)
   🛠️  Development (1/1)
⚠️  Tests skipped: 1/1 (legacy compatibility)
```

## Adding New Tests

### Library Functions
Add to `tests/core/test-lib-functions.nix`:
```nix
testNewFunction = sopswardenLib.newFunction { ... };
assertions = {
  newFunction = testNewFunction.result == expectedValue;
};
```

### User Workflows  
Create `tests/workflows/test-new-workflow.nix`:
```nix
# Test new user workflow
{ pkgs ? import <nixpkgs> {} }:
# Test implementation...
```

### Service Integration
Add to `tests/modules/test-nixos-module.nix`:
```nix
serviceConfigurations = {
  newService = {
    configFile = secretAccessors.new-secret;
  };
};
```

## Test Philosophy

Tests ensure sopswarden's core promise:

1. **Define secrets in NixOS config** - `services.sopswarden.secrets = { ... }`
2. **Use secrets anywhere** - `secrets.secret-name` syntax works everywhere  
3. **Pure evaluation** - Standard `nixos-rebuild switch`
4. **Zero manual steps** - Runtime automation handles everything

Every test validates this end-to-end experience to prevent regressions in user experience.
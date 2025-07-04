# sopswarden Test Suite

This test suite validates all core functionality and user journeys for the sopswarden flake.

## Test Structure

### Core Tests (`core/`)
- **test-pure-evaluation.nix**: Validates basic flake structure and functions work with impure evaluation
- **test-lib-functions.nix**: Tests all library functions in isolation with various inputs
- **test-cyclic-dependencies.nix**: Ensures no circular dependencies during evaluation
- **test-secret-accessors.nix**: Tests mkSecretAccessors function and secrets.* pattern export
- **test-sops-integration.nix**: Tests mkSopsSecrets function and SOPS configuration generation
- **test-change-detection.nix**: Tests hash tracking and file monitoring functionality

### Workflow Tests (`workflows/`)
- **test-fresh-install.nix**: Tests complete user journey from fresh installation
- **test-add-secrets.nix**: Tests adding new secrets to existing configuration

### Module Tests (`modules/`)
- **test-nixos-module.nix**: Tests NixOS module integration and `secrets.secret-name` syntax
- **test-home-manager.nix**: Tests Home Manager module integration

### Integration Tests (`integration/`)
- **test-runtime-sync.nix**: Tests sync script generation and application access to secrets
- **test-rbw-states.nix**: Tests handling of rbw locked/unlocked/unavailable states during build
- **test-secret-path-resolution.nix**: Tests end-to-end secret path resolution

## Running Tests

### Run All Tests
```bash
./tests/run-tests.sh
```

### Run Individual Tests
```bash
# Core functionality test
nix-instantiate --eval --strict --impure tests/core/test-pure-evaluation.nix

# Library functions test
nix-instantiate --eval --strict --impure tests/core/test-lib-functions.nix

# Fresh installation workflow
nix-instantiate --eval --strict --impure tests/workflows/test-fresh-install.nix
```

### Test Package Building
```bash
# Build sync script package
nix build .#sopswarden-sync

# Run flake checks
nix flake check
```

## Test Coverage

The test suite validates:

### ✅ User Journeys
- [x] Fresh installation from scratch
- [x] Adding new secrets to existing configuration
- [x] Using secrets in system services (PostgreSQL, Nginx, etc.)
- [x] Using secrets in Home Manager configurations
- [x] Application access to decrypted secrets

### ✅ Core Functionality
- [x] Flake structure and exports
- [x] Library function correctness
- [x] Secret normalization (simple strings vs complex objects)
- [x] SOPS integration and secret generation
- [x] Sync script generation with various parameters

### ✅ Build Time Behavior
- [x] Evaluation works with `--impure` flag
- [x] No circular dependencies during evaluation
- [x] Handles rbw locked/unlocked/unavailable states
- [x] Package building succeeds
- [x] Flake validation passes

### ✅ Module Integration
- [x] NixOS module options and configuration
- [x] Home Manager module options and configuration
- [x] `secrets.secret-name` syntax availability
- [x] SOPS secrets configuration generation
- [x] System package installation

### ✅ Runtime Integration
- [x] Sync script generation and parameterization
- [x] Systemd service integration
- [x] Secret file access patterns
- [x] Credential loading for applications

## Test Results

All tests should pass with the current impure implementation. The test runner will:

1. Run flake validation (`nix flake check`)
2. Test package building (`nix build .#sopswarden-sync`)
3. Execute all individual test files
4. Validate library functions
5. Report summary of passed/failed tests

Expected output:
```
✅ Tests passed: 15/15
🎉 sopswarden is working correctly
```

## Test Requirements

- **Nix with flakes enabled**
- **jq for JSON parsing**
- **Current implementation requires `--impure` flag**

## Adding New Tests

To add a new test:

1. Create a `.nix` file in the appropriate directory
2. Follow the existing test structure:
   ```nix
   let
     # Test setup
   in {
     # Test results
     success = /* boolean expression */;
     validation = {
       # Detailed validation results
     };
   }
   ```
3. Add the test to `run-tests.sh`
4. Update this README

## Notes

- Tests use `--impure` flag because current implementation uses `builtins.readFile` 
- Tests validate configuration generation, not actual secret syncing
- rbw state tests simulate different rbw availability scenarios
- All tests should pass even when secret files don't exist (tests configuration generation only)
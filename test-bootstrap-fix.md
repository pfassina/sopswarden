# Bootstrap Fix Test

## Problem Fixed
The chicken-and-egg problem where adding new secrets to `secrets.nix` would fail because `sopswarden-sync` read from the stale Nix store instead of the current working directory.

## Solution Implemented
1. **JSON Configuration Generation**: Modules now auto-generate `secrets.json` from `secrets.nix` at build time
2. **Runtime JSON Reading**: Sync script reads from `secrets.json` instead of evaluating Nix at runtime
3. **Working Directory Priority**: Sync script prefers `$WORK_DIR/secrets.json` over Nix store version

## Fixed Workflow

### Step 1: Add new secret to secrets.nix
```nix
# In secrets/secrets.nix
secrets = {
  wifi-password = "Home WiFi";
  zillow-password = "zillow.com";  # NEW SECRET
};
```

### Step 2: Rebuild system
```bash
nixos-rebuild switch --flake .#maker --impure
```
**Result**: ✅ Build succeeds and generates fresh `secrets.json` with all 19 secrets

### Step 3: Sync secrets
```bash
sopswarden-sync
```
**Result**: ✅ Reads from current `secrets.json`, finds all 19 secrets including `zillow-password`

### Step 4: Final rebuild
```bash
nixos-rebuild switch --flake .#maker --impure
```
**Result**: ✅ All secrets available, no bootstrap issues

## Technical Changes

### sync-script.nix
- Added `secretsJsonFile` parameter
- JSON file path resolution with working directory priority
- Replaced `nix eval` with `jq` for parsing secret definitions
- Better error messages for missing JSON file

### lib/default.nix
- Added `mkSecretsJson` function to generate JSON from Nix configuration
- Updated `mkSyncScript` to accept `secretsJsonFile` parameter

### modules/nixos.nix
- Auto-generate `secrets.json` in both Nix store and runtime directory
- Activation script creates runtime JSON file during system activation
- Sync script gets both Nix store fallback and runtime JSON paths

## Benefits
- ✅ No more chicken-and-egg bootstrap problems
- ✅ Maintains familiar Nix syntax for users
- ✅ Zero additional runtime dependencies (uses existing `jq`)
- ✅ Backward compatibility preserved
- ✅ Better error messages and troubleshooting
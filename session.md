# Sopswarden Nix Store Write Issue - Fix Instructions (Final Investigation)

## Issue Summary

The sopswarden-sync script fails with "Read-only file system" error when trying to write the final encrypted output to the Nix store directory.

**Latest Error Message:**
```
🔧 Detected Nix store path, writing to: /nix/store/vqaagdii905hlkp30s1rsz8s8jgpp552-secrets.yaml
/run/current-system/sw/bin/sopswarden-sync: line 168: /nix/store/vqaagdii905hlkp30s1rsz8s8jgpp552-secrets.yaml: Read-only file system
❌ Failed to encrypt secrets with sops
```

## Root Cause Found

The detection logic is working but the path conversion is flawed:

**Current Detection Logic (Lines 26-32):**
```bash
# Handle SOPS_FILE: if it's a Nix store path, write to working directory instead
if [[ "$SOPS_FILE" == /nix/store/* ]]; then
    # Extract filename and write to working directory
    SOPS_FILE="$WORK_DIR/$(basename "$SOPS_FILE")"
    echo "🔧 Detected Nix store path, writing to: $SOPS_FILE"
else
    SOPS_FILE="$(realpath "$SOPS_FILE")"
fi
```

**The Problem:**
`WORK_DIR` itself is set to a Nix store path:
```bash
# Line 18-19
WORK_DIR="$(dirname "$(realpath "$SECRETS_FILE")")"
cd "$WORK_DIR"
```

Since `SECRETS_FILE="/nix/store/.../secrets.nix"`, the `WORK_DIR` becomes `/nix/store/...` (read-only).

So when the script does:
```bash
SOPS_FILE="$WORK_DIR/$(basename "$SOPS_FILE")"
```

It results in: `/nix/store/.../secrets.yaml` (still read-only!)

## The Fix Required

The `WORK_DIR` detection logic needs to be updated to use runtime paths when Nix store paths are detected:

### Current (Broken):
```bash
# Lines 17-19 - Always uses Nix store path
WORK_DIR="$(dirname "$(realpath "$SECRETS_FILE")")"
cd "$WORK_DIR"
```

### Should Be:
```bash
# Detect if SECRETS_FILE is in Nix store and use runtime path instead
if [[ "$SECRETS_FILE" == /nix/store/* ]]; then
    # Use actual runtime directory for NixOS configurations
    WORK_DIR="/home/mead/nix"  # or derive from flake config
else
    # Original behavior for non-Nix environments
    WORK_DIR="$(dirname "$(realpath "$SECRETS_FILE")")"
fi
cd "$WORK_DIR"
```

### Then the existing SOPS_FILE logic works:
```bash
if [[ "$SOPS_FILE" == /nix/store/* ]]; then
    SOPS_FILE="$WORK_DIR/$(basename "$SOPS_FILE")"  # Now writes to /home/mead/nix/secrets.yaml
    echo "🔧 Detected Nix store path, writing to: $SOPS_FILE"
fi
```

## Summary

**Problem:** The script correctly detects Nix store paths but `WORK_DIR` is also a Nix store path, so the "fix" still writes to a read-only location.

**Solution:** Update the `WORK_DIR` logic to use runtime paths when Nix store inputs are detected.

**Key insight:** Both `SECRETS_FILE` and `SOPS_FILE` are Nix store paths, but the working directory should be the actual NixOS configuration directory (`/home/mead/nix`), not the Nix store directory.

## Latest Test Results

**Progress Made:**
✅ WORK_DIR detection now correctly uses `/home/mead/nix` instead of Nix store path
✅ Script correctly detects Nix store paths and uses runtime directory

**New Issue Found:**
❌ Filename extraction is wrong - getting Nix store hash instead of just filename

**Current Output:**
```
🔧 Detected Nix store secrets file, using runtime directory: /home/mead/nix
🔧 Detected Nix store path, writing to: /home/mead/nix/vqaagdii905hlkp30s1rsz8s8jgpp552-secrets.yaml
```

**Should Be:**
```
🔧 Detected Nix store path, writing to: /home/mead/nix/secrets.yaml
```

## Additional Fix Required

The `basename` extraction logic is getting the full Nix store filename instead of the actual filename:

### Current Issue:
```bash
# Input: /nix/store/vqaagdii905hlkp30s1rsz8s8jgpp552-secrets.yaml
# basename result: vqaagdii905hlkp30s1rsz8s8jgpp552-secrets.yaml
```

### Should Extract:
```bash
# Input: /nix/store/vqaagdii905hlkp30s1rsz8s8jgpp552-secrets.yaml  
# desired result: secrets.yaml
```

### Fix Required:
The basename logic needs to strip the Nix store hash prefix and extract just the actual filename:

```bash
# Option 1: Strip everything before the last dash
filename=$(basename "$SOPS_FILE" | sed 's/^[^-]*-//')

# Option 2: Hardcode the expected filename for known files
if [[ "$(basename "$SOPS_FILE")" == *"-secrets.yaml" ]]; then
    filename="secrets.yaml"
fi

# Option 3: Pattern matching
filename=$(basename "$SOPS_FILE" | grep -o '[^-]*\.yaml$')
```

## Alternative Approaches

### Option 1: Fix WORK_DIR Detection (✅ Completed)
Update lines 17-19 to detect Nix store paths and use runtime directory instead.

### Option 2: Fix Basename Extraction (🔄 In Progress)
Update the filename extraction to get just the actual filename, not the Nix store hash.

### Option 3: Hardcode Runtime Paths
Generate the script with runtime paths from the start instead of Nix store paths.

## Files to Modify in Sopswarden Flake

1. **Script template generation** - Where `SOPS_FILE` variable is set
2. **Path resolution logic** - How store paths are converted to runtime paths
3. **Configuration handling** - Ensure runtime paths are available to the script

## Test Commands

After implementing the fix:

```bash
# Update flake
nix flake update sopswarden

# Rebuild system  
sudo nixos-rebuild switch --flake .#maker --impure

# Test auto-sync
nx deploy
```

Expected successful output:
```
🔄 Auto-syncing secrets from Bitwarden...
📡 Fetching: [secrets]...
🔒 Updating existing encrypted secrets file...
✅ Secrets synced successfully
-> NixOS Rebuilding...
```

## Current Script Analysis

The script correctly:
- Uses temp directory for intermediate files ✅
- Fetches secrets from Bitwarden ✅  
- Creates unencrypted YAML in temp location ✅

The script fails at:
- Final encryption output to Nix store path ❌

## Environment Context

- **NixOS flake-based configuration**
- **Runtime config path**: `/home/mead/nix/`
- **Secrets should write to**: `/home/mead/nix/secrets/secrets.yaml`
- **Currently tries to write to**: `/nix/store/.../secrets.yaml` (read-only)
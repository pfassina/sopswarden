# Sopswarden Chicken-and-Egg Problem - Unresolved Bootstrap Issue

## Problem Description

Despite the sopswarden flake claiming to have fixed the bootstrap catch-22 problem, **there remains a fundamental chicken-and-egg issue** that prevents users from successfully adding new secrets to their configuration.

## Current Workflow That Fails

When a user tries to add a new secret (e.g., `zillow-password = "zillow.com"`):

### Step 1: User adds secret to configuration
```nix
# In secrets/secrets.nix
secrets = {
  # existing secrets...
  zillow-password = "zillow.com";  # NEW SECRET
};
```

### Step 2: User attempts to rebuild
```bash
nixos-rebuild switch --flake .#maker --impure
```

**Result**: ✅ Shows helpful warning: `⚠️ sopswarden: secrets.nix has changed since last sync. Run 'sopswarden-sync' to update encrypted secrets.`

**But then**: ❌ **Build fails** with: `secret zillow-password...cannot be found`

### Step 3: User follows guidance to sync secrets
```bash
sopswarden-sync
```

**Result**: ❌ **Sync IGNORES the new secret completely**
- Only syncs 18 existing secrets
- Does NOT fetch `zillow-password` from Bitwarden
- Shows `📝 Encrypted 18 secrets from Bitwarden` (missing the new one)

### Step 4: User tries to rebuild again
```bash
nixos-rebuild switch --flake .#maker --impure
```

**Result**: ❌ **Same failure** - zillow-password still not found in secrets.yaml

## Root Cause: Sopswarden-Sync Reads Stale Configuration

The fundamental issue is that **`sopswarden-sync` reads from the last successful build's Nix store**, not from the current working configuration:

1. **User adds new secret** to `secrets/secrets.nix` ✓
2. **Build fails** because secret not in secrets.yaml ❌
3. **`sopswarden-sync` reads from old Nix store** (before new secret was added) ❌
4. **Sync doesn't include new secret** because it doesn't know about it ❌
5. **User is permanently stuck** - cannot build to update Nix store ❌

## Evidence

### Configuration Has 19 Secrets
```bash
$ nix eval --impure --expr '(builtins.length (builtins.attrNames (import /home/mead/nix/secrets.nix).secrets))'
19
```

### Sopswarden-Sync Only Fetches 18
```bash
$ FORCE_SYNC=true sopswarden-sync | grep "📝 Encrypted"
📝 Encrypted 18 secrets from Bitwarden
```

### Missing Secret Not Even Attempted
```bash
$ FORCE_SYNC=true sopswarden-sync 2>&1 | grep -c "📡 Fetching"
18  # Should be 19
```

## Configuration Details

### Sopswarden Configuration
```nix
services.sopswarden = {
  enable = true;
  secretsFile = rootPath + /secrets/secrets.nix;
  sopsFile = rootPath + /secrets/secrets.yaml;
  sopsConfigFile = rootPath + /.sops.yaml;
  defaultOwner = "mead";
  defaultGroup = "users";
  
  # Import secrets from secrets.nix for NixOS evaluation
  secrets = (import (rootPath + /secrets/secrets.nix)).secrets;
};
```

### Auto-Discovery Output
```
🔧 Detected Nix store secrets file, using runtime directory: /home/mead/nix
🔧 Detected Nix store path, writing to: /home/mead/nix/secrets.yaml
```

## Expected vs Actual Behavior

### Expected (According to README)
1. Add secret to configuration
2. Build shows warning but **succeeds with graceful degradation**
3. Run `sopswarden-sync` to fetch new secret
4. Rebuild succeeds with all secrets available

### Actual
1. Add secret to configuration ✓
2. Build shows warning but **fails at sops layer** ❌
3. `sopswarden-sync` **ignores new secret entirely** ❌
4. User is **permanently stuck** ❌

## Impact

This makes it **impossible for users to add new secrets** to an existing sopswarden setup without manual intervention or workarounds. The bootstrap fix is incomplete.

## Suggested Fix

The `sopswarden-sync` command needs to:

1. **Read from the current working configuration** when it exists, not just the Nix store
2. **Fall back gracefully** when secrets don't exist in Bitwarden
3. **Allow partial sync** where some secrets fail but others succeed
4. **Provide clear guidance** when secrets are missing from the vault

## Test Environment

- **NixOS**: 25.11.20250619.08f2208
- **Sopswarden**: github:pfassina/sopswarden/4e3ca181a37fb4c0e2b00494231cbcd58e1b9606
- **Test Secret**: `zillow-password = "zillow.com"` (verified to exist in Bitwarden vault)
- **Sopswarden Version**: Updated flake with latest bootstrap fixes

The chicken-and-egg problem persists despite the claimed bootstrap improvements.
# sopsWarden

> **SOPS secrets management integrated with Bitwarden for NixOS**

## ⚠️ **Beta Software Warning**

**sopsWarden is currently in beta and under active development.** The configuration format and API may change between versions.

**Before using sopsWarden:**
- 📋 **Backup your existing configurations** - especially `.sops.yaml` and any encrypted files
- 🧪 **Test thoroughly in non-production environments** first  
- 🔄 **Pin to specific flake commits** to avoid unexpected changes
- 📖 **Check the changelog** before updating versions
- 💾 **Keep manual backups** of critical secrets during transition

**Production users:** Consider waiting for v1.0 release unless you're prepared to handle breaking changes.

---

sopsWarden eliminates the pain of manual secret management in NixOS by automatically syncing secrets from your Bitwarden vault to encrypted SOPS files. No more editing encrypted YAML files by hand!

## ✨ Features

- 🔐 **Bitwarden Integration** - Use your existing Bitwarden vault as the source of truth
- 🎯 **In-Configuration Secrets** - Define secrets directly in your NixOS configuration
- 🛡️ **SOPS Encryption** - Secrets encrypted at rest using age keys
- 🚀 **Zero Bootstrap Issues** - Add new secrets without circular dependency problems
- 🔄 **Graceful Degradation** - Missing secrets produce warnings, not build failures
- 🎯 **Type-Safe Access** - Secrets available as `secrets.secret-name` in NixOS configs
- 🏠 **Home Manager Support** - Works with both NixOS and Home Manager
- ⚡ **Zero Manual Encryption** - Never touch encrypted files directly

## 🚀 Quick Start

### 1. Add to your flake

```nix
{
  inputs.sopswarden.url = "github:pfassina/sopswarden";
  
  outputs = { nixpkgs, sopswarden, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        sopswarden.nixosModules.default
        {
          services.sopswarden = {
            enable = true;
            secrets = {
              # Simple secrets - just specify the Bitwarden item name
              wifi-password = "Home WiFi";
              database-url = "Production Database";
              
              # Complex secrets - specify user, type, or field
              api-key = { name = "My Service"; user = "admin@example.com"; };
              ssl-cert = { name = "Certificates"; type = "note"; field = "ssl_cert"; };
            };
          };
        }
      ];
    };
  };
}
```

### 2. Setup encryption

```bash
# Generate age key
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Create .sops.yaml with your public key
cat > .sops.yaml << EOF
keys:
  - &main_key $(age-keygen -y ~/.config/sops/age/keys.txt)
creation_rules:
  - path_regex: secrets\.ya?ml$
    key_groups:
    - age: [*main_key]
EOF
```

### 3. Configure rbw with NixOS

```nix
# Add to your NixOS configuration or Home Manager
programs.rbw = {
  enable = true;
  settings = {
    email = "your-email@example.com";
    # For self-hosted Bitwarden:
    base_url = "https://your-bitwarden-server.com";
    lock_timeout = 3600;
    pinentry = pkgs.pinentry-curses;
  };
};
```

Then unlock your vault:
```bash
rbw unlock
```

### 4. Sync and deploy

```bash
sopswarden-sync    # Fetch secrets from Bitwarden and encrypt
nixos-rebuild switch --flake .#myhost --impure
```

## 📖 How It Works

```
Bitwarden Vault → sopswarden-sync → secrets.yaml (encrypted) → NixOS Build → /run/secrets/ (decrypted) → Applications
```

1. **Store** secrets in Bitwarden (login items + secure notes)
2. **Define** secret mappings in `secrets.nix`
3. **Sync** with `sopswarden-sync` to fetch and encrypt
4. **Build** NixOS with `--impure` flag to read secrets
5. **Use** secrets as `secrets.secret-name` in configurations

## 🚀 Adding New Secrets (Bootstrap Mode)

When adding new secrets to an existing system, use **bootstrap mode** to avoid circular dependency issues:

### Quick Bootstrap Workflow

```nix
# 1. Enable bootstrap mode and add new secrets
services.sopswarden = {
  enable = true;
  bootstrapMode = true;  # 🔧 Enable during bootstrap
  secrets = {
    # ... existing secrets ...
    new-secret = "New Bitwarden Item";  # ✅ Add new secrets
  };
};
```

```bash
# 2. Build system successfully  
nixos-rebuild switch --flake .#hostname --impure

# 3. Sync new secrets from Bitwarden
sopswarden-sync

# 4. Disable bootstrap mode
# Remove `bootstrapMode = true;` from configuration

# 5. Final rebuild
nixos-rebuild switch --flake .#hostname --impure
```

### Why Bootstrap Mode?

Without bootstrap mode, adding new secrets creates a chicken-and-egg problem:
- ❌ Build fails because new secrets don't exist in secrets.yaml yet
- ❌ Can't run sopswarden-sync because system won't build to generate updated sync script
- ❌ Can't update sync script because build fails

Bootstrap mode solves this by:
- ✅ Bypassing SOPS validation for missing secrets during builds
- ✅ Allowing sopswarden-sync to be generated with new secret definitions
- ✅ Enabling the complete bootstrap workflow

## 🔧 Configuration

### Secret Types

#### Simple Login Items
```nix
api-key = "My Service";  # Uses password field from "My Service" login item
```

#### Login Items with Specific Users
```nix
database-password = {
  name = "Database Server";
  user = "admin@production.com";  # When multiple accounts exist
};
```

#### Secure Notes with Custom Fields
```nix
ssl-certificate = {
  name = "SSL Config";
  type = "note";
  field = "certificate";  # Custom field in secure note
};
```

### rbw Configuration Examples

#### Self-hosted Bitwarden
```nix
programs.rbw = {
  enable = true;
  settings = {
    email = "admin@company.com";
    base_url = "https://vault.company.com";
    lock_timeout = 3600;
    pinentry = pkgs.pinentry-gtk2;  # or pinentry-curses for headless
  };
};
```

#### Bitwarden.com (Official)
```nix
programs.rbw = {
  enable = true;
  settings = {
    email = "user@example.com";
    lock_timeout = 3600;
    # base_url not needed for official Bitwarden
  };
};
```

### Advanced Options

```nix
services.sopswarden = {
  enable = true;
  
  # File locations (use string paths to avoid caching issues)
  sopsFile = "./config/secrets.yaml";      # Relative path
  sopsConfigFile = "./config/.sops.yaml"; # SOPS configuration
  ageKeyFile = "/custom/path/keys.txt";    # Absolute path for age keys
  
  # rbw configuration  
  rbwCommand = "${pkgs.rbw}/bin/rbw";  # Custom rbw command
  
  # Secret permissions
  defaultOwner = "myuser";
  defaultGroup = "users";
  defaultMode = "0440";
  
  # Package management
  installPackages = true;  # Install rbw, sops, age, jq
  enableChangeDetection = true;  # Warn when secrets.nix changes
};
```

## 🏠 Home Manager Integration

```nix
{
  programs.sopswarden = {
    enable = true;
    secretsFile = ./user-secrets.nix;
    sopsFile = ./user-secrets.yaml;
  };
  
  # Configure rbw for the user
  programs.rbw = {
    enable = true;
    settings = {
      email = "user@example.com";
      base_url = "https://your-server.com";
    };
  };
}
```

## 🔄 Workflow

### First-Time Setup

Adding secrets to a new NixOS system is now straightforward:

1. **Add secrets to your configuration:**
   ```nix
   services.sopswarden = {
     enable = true;
     secrets = {
       wifi-password = "Home WiFi";
       api-key = "My Service";
       database-password = { name = "DB Server"; user = "admin"; };
     };
   };
   ```

2. **Rebuild to install sopswarden:**
   ```bash
   nixos-rebuild switch --flake .#host --impure
   ```
   
   ✅ **Always succeeds** - no bootstrap issues!
   ```
   ⚠️  sopswarden: secrets.yaml not found. Run 'sopswarden-sync' to create it.
   ```

3. **Sync secrets and rebuild:**
   ```bash
   sopswarden-sync                              # Fetch and encrypt all secrets
   nixos-rebuild switch --flake .#host --impure  # Final rebuild with secrets
   ```

### Adding New Secrets

✅ **Zero bootstrap issues** - adding secrets is seamless!

1. **Add to Bitwarden** (web interface or `rbw`)
2. **Update your configuration:**
   ```nix
   services.sopswarden.secrets = {
     # existing secrets...
     new-secret = "New Bitwarden Item";  # Add this line
   };
   ```
3. **Rebuild:** `nixos-rebuild switch --flake .#host --impure`
   - ✅ **Always succeeds** - new secrets immediately available to sync script
   - ⚠️ Shows helpful warning about missing secrets file
4. **Sync:** `sopswarden-sync` ✅ **Finds all secrets including new ones**
5. **Final rebuild:** `nixos-rebuild switch --flake .#host --impure`

### Updating Existing Secrets

1. **Update in Bitwarden**
2. **Sync:** `sopswarden-sync`  
3. **Deploy:** `nixos-rebuild switch --flake .#host --impure`

### Smart Change Detection

sopsWarden automatically detects when `secrets.nix` changes:
- ✅ **Skip sync** when no changes detected
- ⚠️ **Show warnings** during build when sync needed
- 🔄 **Auto-sync** with deployment tools


## 📚 Examples

- **[Basic Example](./examples/basic/)** - Simple setup with common secrets
- **[Advanced Example](./examples/advanced/)** - Complex multi-service configuration
- **[Migration Guide](./examples/migration/)** - Migrating from manual sops-nix

## 🛡️ Security

- ✅ **Encrypted at rest** - Secrets encrypted in git repository
- ✅ **Age encryption** - Industry-standard encryption with age keys  
- ✅ **Proper permissions** - Runtime secrets protected with file permissions
- ✅ **No secret exposure** - Hash-based change detection prevents unnecessary decryption
- ✅ **Graceful failures** - Never blocks deployment if Bitwarden unavailable

## 🚀 User Experience

### Simplified Configuration

Define secrets directly in your NixOS configuration - no separate files to manage:

```nix
services.sopswarden.secrets = {
  wifi-password = "Home WiFi";              # Simple secrets
  api-key = { name = "API"; user = "admin"; };  # Complex secrets  
};
```

### Graceful Error Handling

**Clear warnings instead of build failures:**
```
⚠️  sopswarden: secrets.yaml not found. Run 'sopswarden-sync' to create it.
⚠️  Warning: Failed to fetch 'Missing Item' - skipping
📝 Successfully encrypted 5 secrets from Bitwarden
```

### Zero Bootstrap Issues

- ✅ **No circular dependencies** - Secrets defined in configuration, not files
- ✅ **Immediate availability** - New secrets ready to sync after rebuild
- ✅ **Graceful degradation** - Missing secrets produce warnings, not failures
- ✅ **Preserved API** - `secrets.secret-name` syntax always works

## 🏗️ Architecture

### In-Configuration Design

sopsWarden uses a modern approach that eliminates file dependencies:

- **Direct Configuration**: Secrets defined as NixOS options, not external files
- **Build-Time Generation**: Sync script generated with embedded secret definitions  
- **Zero File Dependencies**: No reading from `secrets.nix`, `secrets.json`, or config files
- **Immediate Availability**: New secrets ready to sync the moment they're added

### How It Works

```nix
# 1. User defines secrets in configuration
services.sopswarden.secrets = {
  wifi-password = "Home WiFi";
};

# 2. Build generates sync script with embedded secrets
# 3. Script fetches directly from Bitwarden - no file reading needed
# 4. Graceful degradation if secrets missing from vault
```

### Benefits

- ✅ **No bootstrap problems** - Secrets available immediately after rebuild
- ✅ **Simplified architecture** - No complex path resolution or file detection
- ✅ **Better error handling** - Clear warnings instead of cryptic failures
- ✅ **Flake compatible** - Works seamlessly in any Nix environment

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](./CONTRIBUTING.md) for details.

## 📄 License

MIT License - see [LICENSE](./LICENSE) for details.

## 🙏 Acknowledgments

- [sops-nix](https://github.com/Mic92/sops-nix) for the underlying SOPS integration
- [rbw](https://github.com/doy/rbw) for excellent Bitwarden CLI interface
- [age](https://github.com/FiloSottile/age) for modern encryption

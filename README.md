# sopsWarden

> **SOPS secrets management integrated with Bitwarden for NixOS**

Sopswarden eliminates the pain of manual secret management in NixOS by automatically syncing secrets from your Bitwarden vault to encrypted SOPS files. No more editing encrypted YAML files by hand!

## ✨ Features

- 🔐 **Bitwarden Integration** - Use your existing Bitwarden vault as the source of truth
- 🤖 **Automatic Syncing** - Smart change detection with hash-based tracking
- 🛡️ **SOPS Encryption** - Secrets encrypted at rest using age keys
- 🎯 **Type-Safe Access** - Secrets available as `secrets.secret-name` in NixOS configs
- 🔄 **Graceful Error Handling** - Never blocks deployment if Bitwarden is locked
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
              wifi-password = "Home WiFi";  # Simple: uses password field
              api-key = { name = "My Service"; user = "admin@example.com"; };  # Complex: specific user
              ssl-cert = { name = "Certificates"; type = "note"; field = "ssl_cert"; };  # Note field
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
  
  # File locations
  secretsFile = ./config/secrets.nix;
  sopsFile = ./config/secrets.yaml;
  ageKeyFile = "/custom/path/keys.txt";
  
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

### Adding New Secrets

1. **Add to Bitwarden** (web interface or `rbw`)
2. **Update secrets.nix** with mapping
3. **Sync:** `sopswarden-sync` 
4. **Deploy:** `nixos-rebuild switch --flake .#host --impure`

### Updating Existing Secrets

1. **Update in Bitwarden**
2. **Sync:** `sopswarden-sync`  
3. **Deploy:** `nixos-rebuild switch --flake .#host --impure`

### Smart Change Detection

Sopswarden automatically detects when `secrets.nix` changes:
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

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](./CONTRIBUTING.md) for details.

## 📄 License

MIT License - see [LICENSE](./LICENSE) for details.

## 🙏 Acknowledgments

- [sops-nix](https://github.com/Mic92/sops-nix) for the underlying SOPS integration
- [rbw](https://github.com/doy/rbw) for excellent Bitwarden CLI interface
- [age](https://github.com/FiloSottile/age) for modern encryption

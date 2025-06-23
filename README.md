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
- 🎯 **Simple Configuration** - Define secrets directly in your NixOS configuration
- 🛡️ **SOPS Encryption** - Secrets encrypted at rest using age keys
- 🚀 **Pure Evaluation** - No `--impure` flags or bootstrap modes required
- 🔄 **Graceful Degradation** - Missing secrets produce warnings, not build failures
- 🎯 **Ergonomic Access** - Secrets available as `secrets.secret-name` in NixOS configs
- ⚡ **Automatic Sync** - Runtime synchronization via systemd services

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

### 4. Deploy

```bash
# Secrets are automatically synced during system activation
nixos-rebuild switch --flake .#myhost
```

## 🔐 Using Secrets in NixOS

Once you've defined secrets, they become available throughout your NixOS configuration. Add `secrets` to your module arguments to access them:

```nix
# Add 'secrets' to your module arguments
{ config, pkgs, secrets, ... }: {
  # Define secrets once
  services.sopswarden.secrets = {
    wifi-password = "Home WiFi";
    api-key = { name = "My Service"; user = "admin@example.com"; };
    ssl-cert = { name = "Certificates"; type = "note"; field = "certificate"; };
  };

  # Use them anywhere in your NixOS configuration
  networking.wireless.networks."MyWiFi".psk = secrets.wifi-password;
  services.nginx.virtualHosts."api.example.com".extraConfig = ''
    proxy_set_header Authorization "Bearer ${secrets.api-key}";
  '';
  environment.etc."ssl/cert.pem".text = secrets.ssl-cert;
}
```

### Common Usage Examples

```nix
{ config, pkgs, secrets, ... }: {
  services.sopswarden.secrets = {
    db-password = "Database Admin";
    api-token = "Service API Key";
  };

  # Database configuration
  services.postgresql.initialScript = pkgs.writeText "init.sql" ''
    CREATE USER app WITH PASSWORD '${secrets.db-password}';
  '';

  # Systemd service with secret
  systemd.services.my-app = {
    serviceConfig.EnvironmentFile = secrets.api-token;
  };

  # Container with environment variable
  virtualisation.oci-containers.containers.web-app = {
    image = "nginx:latest";
    environment.API_KEY = secrets.api-token;
  };
}
```

### ⚠️ rbw Configuration Caveat

**Do not use `secrets.*` for configuring rbw itself** - this creates circular dependencies since rbw is needed to fetch the secrets. Configure rbw directly in your NixOS configuration:

```nix
# ✅ Correct - configure rbw directly
programs.rbw = {
  enable = true;
  settings = {
    email = "user@example.com";  # Direct configuration
    base_url = "https://vault.example.com";
  };
};

# ❌ Avoid - don't use secrets for rbw config
programs.rbw.settings.email = secrets.rbw-email;  # This won't work
```

Support for using secrets in rbw configuration is under development.

### 🧪 Home Manager Support

Home Manager integration is currently **experimental**. While a Home Manager module exists, the `secrets.*` pattern may not work as expected in Home Manager configurations. Investigation is ongoing to determine the best approach for Home Manager secrets integration.

For now, use sopsWarden primarily with NixOS system-level configurations.

## 📖 How It Works

```
Bitwarden Vault → systemd sync → secrets.yaml (encrypted) → /run/secrets/ (decrypted) → Applications
```

1. **Store** secrets in Bitwarden (login items + secure notes)
2. **Define** secret mappings in your NixOS configuration
3. **Deploy** with `nixos-rebuild switch` 
4. **Automatic sync** happens via systemd services during activation
5. **Use** secrets as `secrets.secret-name` in configurations

## 🚀 Adding New Secrets

Adding new secrets is now completely seamless - no bootstrap modes or special procedures required:

```nix
# Simply add to your configuration
services.sopswarden.secrets = {
  # ... existing secrets ...
  new-secret = "New Bitwarden Item";  # ✅ Just add this line
};
```

```bash
# Deploy normally
nixos-rebuild switch --flake .#hostname

# Secrets are automatically synced during system activation!
```

The system automatically handles:
- ✅ **New secret detection** - Finds new secrets in your configuration
- ✅ **Graceful sync** - Fetches from Bitwarden during activation  
- ✅ **Error handling** - Missing secrets produce warnings, not failures
- ✅ **Pure evaluation** - No `--impure` flags or complex workflows needed

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
  sopsFile = "/var/lib/sopswarden/secrets.yaml";      # Custom location
  sopsConfigFile = "/var/lib/sopswarden/.sops.yaml";  # SOPS configuration
  ageKeyFile = "/custom/path/keys.txt";               # Custom age keys
  
  # rbw configuration  
  rbwCommand = "${pkgs.rbw}/bin/rbw";  # Custom rbw command
  
  # Secret permissions
  defaultOwner = "myuser";
  defaultGroup = "users";
  defaultMode = "0440";
  
  # Package management
  installPackages = true;  # Install rbw, sops, age
};
```

## 🏠 Home Manager Integration

```nix
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

### Setup and Usage

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

2. **Deploy:**
   ```bash
   nixos-rebuild switch --flake .#host
   ```
   
   Secrets are automatically synced during system activation!

### Adding New Secrets

1. **Add to Bitwarden** (web interface or `rbw`)
2. **Update your configuration** (add the new secret)
3. **Deploy:** `nixos-rebuild switch --flake .#host`

### Updating Existing Secrets

1. **Update in Bitwarden**
2. **Deploy:** `nixos-rebuild switch --flake .#host`

The system automatically handles synchronization during deployment.


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

### Simple Configuration

Define secrets directly in your NixOS configuration:

```nix
services.sopswarden.secrets = {
  wifi-password = "Home WiFi";              # Simple secrets
  api-key = { name = "API"; user = "admin"; };  # Complex secrets  
};
```

### Graceful Error Handling

Clear warnings instead of build failures:
```
⚠️  Warning: Failed to fetch 'Missing Item' - skipping
📝 Successfully encrypted 5 secrets from Bitwarden
```

### Pure Evaluation Benefits

- ✅ **No `--impure` flags** - Standard Nix evaluation
- ✅ **No bootstrap modes** - Just add secrets and deploy
- ✅ **Automatic sync** - Runtime synchronization via systemd
- ✅ **Preserved API** - `secrets.secret-name` syntax always works

## 🏗️ Architecture

sopsWarden uses pure evaluation with runtime synchronization:

- **Pure Evaluation**: Never reads files during `nixos-rebuild`
- **Runtime Sync**: systemd services handle Bitwarden integration  
- **Direct Configuration**: Secrets defined as NixOS options
- **Automatic Management**: No manual secret file editing required

### Benefits

- ✅ **Standard Nix workflow** - No special flags or procedures
- ✅ **Simplified deployment** - Just `nixos-rebuild switch`
- ✅ **Better error handling** - Clear warnings instead of build failures
- ✅ **Flake compatible** - Works seamlessly in any Nix environment

## 🔧 Troubleshooting

### Common Issues

**Error**: `rbw unlock` required
```bash
rbw unlock  # Enter your Bitwarden master password
```

**Error**: Secrets not found in Bitwarden
```
⚠️  Warning: Failed to fetch 'Missing Item' - skipping
```
Check that the item name in Bitwarden matches your configuration.

**Error**: `sops` command not found
```bash
# Ensure sopswarden packages are installed
services.sopswarden.installPackages = true;  # In your config
```

### Configuration

**Default file locations:**
```
/var/lib/sopswarden/
├── secrets.yaml         # Encrypted secrets
└── .sops.yaml          # SOPS configuration
```

**Age keys:** `~/.config/sops/age/keys.txt`

### Git Integration

**The encrypted `secrets.yaml` is safe to commit:**
```bash
git add secrets.yaml     # Encrypted file - safe to share
git add .sops.yaml       # SOPS config - safe to share  
git commit -m "Add encrypted secrets"
```

**Private keys should NOT be committed:**
```bash
echo "*.txt" >> .gitignore  # Age private keys
echo ".env" >> .gitignore   # Environment files
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](./CONTRIBUTING.md) for details.

## 📄 License

MIT License - see [LICENSE](./LICENSE) for details.

## 🙏 Acknowledgments

- [sops-nix](https://github.com/Mic92/sops-nix) for the underlying SOPS integration
- [rbw](https://github.com/doy/rbw) for excellent Bitwarden CLI interface
- [age](https://github.com/FiloSottile/age) for modern encryption

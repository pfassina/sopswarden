# sopsWarden (Impure Implementation)

> **SOPS secrets management integrated with Bitwarden for NixOS**

## ⚠️ **Impure Implementation Notice**

This branch contains the **impure implementation** of sopsWarden that requires the `--impure` flag for NixOS evaluation. This implementation provides direct access to decrypted secret values in your configuration by reading them at evaluation time.

**Key differences:**
- ✅ **Direct secret access** - Secrets available as actual values, not just paths
- ⚠️ **Requires `--impure`** - All NixOS rebuilds need the `--impure` flag
- 🔄 **Evaluation-time reading** - Secrets are read during configuration evaluation

---

sopsWarden eliminates the pain of manual secret management in NixOS by automatically syncing secrets from your Bitwarden vault to encrypted SOPS files. No more editing encrypted YAML files by hand!

## ✨ Features

- 🔐 **Bitwarden Integration** - Use your existing Bitwarden vault as the source of truth
- 🎯 **Simple Configuration** - Define secrets directly in your NixOS configuration
- 🛡️ **SOPS Encryption** - Secrets encrypted at rest using age keys
- 💡 **Direct Access** - Secrets available as actual values in your configuration
- 🔄 **Change Detection** - Automatic warnings when secrets need re-syncing
- ⚠️ **Impure Evaluation** - Requires `--impure` flag for all operations

## 🚀 Quick Start

### 1. Add to your flake

```nix
{
  inputs.sopswarden.url = "github:pfassina/sopswarden/impure-implementation";
  
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

### 3. Configure rbw

```bash
# Login to Bitwarden
rbw login your-email@example.com

# For self-hosted Bitwarden
rbw config set base_url https://your-bitwarden-server.com

# Unlock vault
rbw unlock
```

### 4. Sync secrets

```bash
# Run initial sync
sopswarden-sync

# This creates an encrypted secrets.yaml file
```

### 5. Deploy with --impure

```bash
# IMPORTANT: Always use --impure flag
sudo nixos-rebuild switch --flake .#myhost --impure
```

## 🔐 Using Secrets in NixOS

With the impure implementation, secrets are available as **actual values** in your configuration:

```nix
# Add 'secrets' to your module arguments
{ config, pkgs, secrets, ... }: {
  # Define secrets once
  services.sopswarden.secrets = {
    wifi-password = "Home WiFi";
    api-key = { name = "My Service"; user = "admin@example.com"; };
    db-password = "Database Password";
  };

  # Use actual secret values directly
  networking.wireless.networks."MyWiFi".psk = secrets.wifi-password;  # Actual password string
  
  services.postgresql.initialScript = pkgs.writeText "init.sql" ''
    CREATE USER app WITH PASSWORD '${secrets.db-password}';  # Direct value
  '';
  
  services.myapp = {
    apiKey = secrets.api-key;  # Direct access to decrypted value
  };
}
```

### Key Difference: Direct Values vs Paths

```nix
# Impure implementation (this branch)
environment.etc."api-config".text = ''
  API_KEY=${secrets.api-key}  # Direct value: "sk-1234567890abcdef"
'';

# Pure implementation (main branch)  
environment.etc."api-config".text = ''
  API_KEY=$(cat ${secrets.api-key})  # Path: /run/secrets/api-key
'';
```

## 📖 How It Works

The impure implementation uses `builtins.readFile` to read decrypted secrets during evaluation:

1. **Sync** - `sopswarden-sync` fetches from Bitwarden and creates encrypted `secrets.yaml`
2. **Deploy** - `nixos-rebuild switch --impure` runs
3. **Decrypt** - SOPS decrypts secrets to `/run/secrets/*`
4. **Read** - Configuration reads actual values using `builtins.readFile`
5. **Use** - Secrets available as strings in your configuration

## 🔄 Workflow

### Adding New Secrets

1. **Add to Bitwarden** (web interface or `rbw`)
2. **Update configuration:**
   ```nix
   services.sopswarden.secrets = {
     # ... existing secrets ...
     new-secret = "New Bitwarden Item";
   };
   ```
3. **Sync secrets:**
   ```bash
   sopswarden-sync
   ```
4. **Deploy with --impure:**
   ```bash
   sudo nixos-rebuild switch --flake .#host --impure
   ```

### Automatic Change Detection

The module will warn you when secrets need syncing:
```
⚠️  sopswarden: secrets file has changed since last sync. Run 'sopswarden-sync' to update encrypted secrets.
```

## 🔧 Configuration Options

```nix
services.sopswarden = {
  enable = true;
  
  # File locations
  secretsFile = ./secrets.nix;          # Your secret definitions
  sopsFile = ./secrets.yaml;            # Encrypted output
  ageKeyFile = "~/.config/sops/age/keys.txt";
  
  # rbw configuration  
  rbwCommand = "${pkgs.rbw}/bin/rbw";
  
  # Secret permissions
  defaultOwner = "root";
  defaultGroup = "root"; 
  defaultMode = "0400";
  
  # Features
  enableChangeDetection = true;  # Warn when sync needed
  installPackages = true;        # Install rbw, sops, age
  installSyncCommand = true;     # Install sopswarden-sync
};
```

## 🛡️ Security Considerations

### Impure Evaluation Trade-offs

**Benefits:**
- ✅ Direct access to secret values
- ✅ Simpler syntax in configurations
- ✅ No need to use `cat` or file reading

**Drawbacks:**
- ⚠️ Requires `--impure` flag always
- ⚠️ Secrets accessible during evaluation
- ⚠️ Can't use with restricted evaluation modes

### Best Practices

1. **Never commit unencrypted secrets**
2. **Keep your age keys secure** 
3. **Use strong Bitwarden master password**
4. **Regularly rotate secrets**
5. **Audit secret access in configurations**

## 🚀 Tips for Impure Usage

### Deployment Script

Create a deployment helper:
```bash
#!/usr/bin/env bash
# deploy.sh
set -e

echo "🔄 Checking for secret changes..."
if sopswarden-sync; then
  echo "✅ Secrets synced"
fi

echo "🚀 Deploying configuration..."
sudo nixos-rebuild switch --flake .#$(hostname) --impure
```

### Integration with nx-deploy style workflow

```nix
# Create a custom deployment command
environment.systemPackages = [
  (pkgs.writeShellScriptBin "nx-deploy" ''
    # Auto-sync if rbw is unlocked
    if rbw ls &>/dev/null; then
      sopswarden-sync
    else
      echo "⚠️  rbw is locked, using existing secrets"
    fi
    
    # Deploy with impure flag
    sudo nixos-rebuild switch --flake /etc/nixos#$(hostname) --impure
  '')
];
```

## 🔧 Troubleshooting

### Common Issues

**Error**: Forgetting `--impure` flag
```
error: access to path '/run/secrets/...' is forbidden in pure eval mode
```
Solution: Always use `--impure` flag

**Error**: Secrets not yet synced
```
error: getting status of '/run/secrets/wifi-password': No such file or directory
```
Solution: Run `sopswarden-sync` first

**Error**: rbw not unlocked
```
Error: rbw is not authenticated. Please run 'rbw login' first.
```
Solution: `rbw unlock`

## 📄 License

MIT License - see [LICENSE](./LICENSE) for details.
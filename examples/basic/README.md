# Basic Sopswarden Example

This example shows the simplest way to use sopswarden in your NixOS configuration.

## Setup

1. **Generate age key:**
   ```bash
   mkdir -p ~/.config/sops/age
   age-keygen -o ~/.config/sops/age/keys.txt
   ```

2. **Update .sops.yaml with your age key:**
   ```bash
   # Get your public key
   age-keygen -y ~/.config/sops/age/keys.txt
   
   # Replace the key in .sops.yaml
   ```

3. **Configure rbw in your NixOS configuration:**
   ```nix
   # Add to your NixOS configuration or Home Manager
   programs.rbw = {
     enable = true;
     settings = {
       email = "your-email@example.com";
       base_url = "https://your-bitwarden-server.com";  # Optional: for self-hosted
       lock_timeout = 3600;
       pinentry = pkgs.pinentry-curses;
     };
   };
   ```
   
   Then rebuild and unlock:
   ```bash
   sudo nixos-rebuild switch --flake .#example
   rbw unlock
   ```

4. **Add secrets to Bitwarden:**
   - Create login item "My API Service" with your API key as password
   - Create login item "Database Server" with user "admin@example.com" and database password
   - Create secure note "Home WiFi" with custom field "password" containing WiFi password

5. **Sync secrets:**
   ```bash
   sopswarden-sync
   ```

6. **Build your system:**
   ```bash
   sudo nixos-rebuild switch --flake .#example --impure
   ```

## Usage

After setup, your secrets are available in NixOS configuration as `secrets.secret-name`:

```nix
{ secrets, ... }: {
  # Use in any NixOS module
  services.myapp.apiKey = secrets.api-key;
  services.postgresql.password = secrets.database-password;
  networking.wireless.networks."MyNetwork".psk = secrets.wifi-password;
}
```

## Workflow

1. **Add new secret to Bitwarden** (web interface or rbw)
2. **Update `secrets.nix`** with the new secret definition
3. **Sync:** `sopswarden-sync` (automatically detects changes)
4. **Rebuild:** `sudo nixos-rebuild switch --flake .#example --impure`

The `--impure` flag is needed because NixOS reads the decrypted secret files during evaluation.
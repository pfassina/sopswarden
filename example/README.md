# Basic Sopswarden Example

This example shows the simplest way to use sopswarden in your NixOS configuration.

## Setup

1. **Generate age key:**
   ```bash
   mkdir -p ~/.config/sops/age
   age-keygen -o ~/.config/sops/age/keys.txt
   ```

2. **sopswarden will automatically create .sops.yaml:**
   ```bash
   # No manual configuration needed!
   # sopswarden-sync will create .sops.yaml in /var/lib/sopswarden/
   # when you run it for the first time
   ```

3. **Configure rbw:**
   ```nix
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

4. **Add secrets to Bitwarden:**
   - Create login item "My API Service" with your API key as password
   - Create login item "Database Server" with user "admin@example.com" and database password  
   - Create secure note "Home WiFi" with custom field "password" containing WiFi password

5. **Deploy:**
   ```bash
   rbw unlock  # Unlock Bitwarden
   sopswarden-sync  # Sync secrets from Bitwarden
   nixos-rebuild switch --flake .#example --impure
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
2. **Update your flake.nix** with the new secret in `services.sopswarden.secrets`:
   ```nix
   services.sopswarden.secrets = {
     # ... existing secrets ...
     new-secret = "New Bitwarden Item Name";
   };
   ```
3. **Deploy:**
   ```bash
   sopswarden-sync  # Sync from Bitwarden
   nixos-rebuild switch --flake .#example --impure
   ```
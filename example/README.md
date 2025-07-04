# Basic Sopswarden Example

This example shows the simplest way to use sopswarden in your NixOS configuration.

## Setup

1. **Generate age key:**
   ```bash
   mkdir -p ~/.config/sops/age
   age-keygen -o ~/.config/sops/age/keys.txt
   ```

2. **Create .sops.yaml with your age key:**
   ```bash
   # Get your public key and create config
   cat > .sops.yaml << EOF
   keys:
     - &main_key $(age-keygen -y ~/.config/sops/age/keys.txt)
   creation_rules:
     - path_regex: secrets\.ya?ml$
       key_groups:
       - age: [*main_key]
   EOF
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
   nixos-rebuild switch --flake .#example
   ```
   
   Secrets are automatically synced during system activation!

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
2. **Update your flake.nix** with the new secret definition
3. **Deploy:** `nixos-rebuild switch --flake .#example`

Secrets are automatically synced during system activation - no manual steps required!
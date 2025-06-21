# Advanced Sopswarden Example

This example demonstrates advanced sopswarden usage with:
- Custom file locations
- Multiple secret types and patterns
- Integration with various services
- Home Manager integration
- Custom deployment workflow

## Features Demonstrated

### Secret Organization
- **Database secrets** with multiple users/environments
- **API keys** for different environments  
- **Infrastructure secrets** (VPN, SSL, networking)
- **Service credentials** (Grafana, email, monitoring)
- **Backup encryption** keys

### Advanced Configuration
- Custom file paths for secrets and configuration
- Custom rbw command configuration
- Custom ownership and permissions
- Integration with system services

### Home Manager Integration
- User-level secret management
- Separate secret files for user vs system secrets

## Directory Structure

```
config/
├── .sops.yaml           # SOPS encryption configuration
├── secrets.nix          # System-level secret definitions  
├── secrets.yaml         # Encrypted system secrets (generated)
├── user-secrets.nix     # User-level secret definitions
└── user-secrets.yaml    # Encrypted user secrets (generated)
```

## Setup

1. **Setup age keys for both system and user:**
   ```bash
   # System key (for root)
   sudo mkdir -p /root/.config/sops/age
   sudo age-keygen -o /root/.config/sops/age/keys.txt
   
   # User key
   mkdir -p ~/.config/sops/age  
   age-keygen -o ~/.config/sops/age/keys.txt
   ```

2. **Update .sops.yaml with both keys:**
   ```yaml
   keys:
     - &system_key age1xxxxx...  # System key
     - &user_key age1yyyyy...    # User key
   
   creation_rules:
     - path_regex: config/secrets\.ya?ml$
       key_groups:
       - age: [*system_key]
     - path_regex: config/user-secrets\.ya?ml$  
       key_groups:
       - age: [*user_key]
   ```

3. **Configure rbw and add secrets to Bitwarden**

4. **Sync and deploy:**
   ```bash
   deploy-with-secrets
   ```

## Secret Patterns

### Multiple Environments
```nix
api-key-production = { name = "Service API"; user = "prod@company.com"; };
api-key-staging = { name = "Service API"; user = "staging@company.com"; };
```

### Complex Service Configuration
```nix
smtp-host = { name = "Email Config"; type = "note"; field = "smtp_host"; };
smtp-port = { name = "Email Config"; type = "note"; field = "smtp_port"; };
smtp-user = { name = "Email Config"; type = "note"; field = "smtp_user"; };
smtp-password = { name = "Email Config"; type = "note"; field = "smtp_password"; };
```

### Infrastructure Secrets
```nix
vpn-config = { name = "Infrastructure"; type = "note"; field = "vpn_config"; };
ssl-cert = { name = "Infrastructure"; type = "note"; field = "ssl_certificate"; };
```

This example shows how sopswarden scales to complex, production-ready configurations.
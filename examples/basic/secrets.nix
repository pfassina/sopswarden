# secrets.nix - Define which secrets to sync from Bitwarden
{
  secrets = {
    # Simple login item (uses password field)
    api-key = "My API Service";
    
    # Login item with specific user account
    database-password = {
      name = "Database Server";
      user = "admin@example.com";
    };
    
    # Secure note with custom field
    wifi-password = {
      name = "Home WiFi";
      type = "note";
      field = "password";
    };
    
    # More examples:
    # github-token = { name = "GitHub"; user = "work@example.com"; };
    # smtp-password = { name = "Email Config"; type = "note"; field = "smtp_password"; };
  };
}
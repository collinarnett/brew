{config, ...}: {
  virtualisation.oci-containers.containers.authelia = {
    image = "authelia/authelia";
    ports = ["9091:9091"];
    volumes = [
      "${./configuration.yml}:/config/configuration.yml"
      "${./user_database.yml}:/config/user_database.yml"
      "${config.sops.secrets.authelia_jwt_secret_file.path}:/config/authelia_jwt_secret_file"
      "${config.sops.secrets.authelia_session_secret_file.path}:/config/authelia_session_secret_file"
      "${config.sops.secrets.authelia_storage_encryption_key_file.path}:/config/authelia_storage_encryption_key_file"
      #      "${config.sops.secrets.authelia_session_redis_password_file.path}:/config/authelia_session_redis_password_file"
    ];
    environment = {
      TZ = "America/New_York";
      AUTHELIA_JWT_SECRET_FILE = "/config/authelia_jwt_secret_file";
      AUTHELIA_SESSION_SECRET_FILE = "/config/authelia_session_secret_file";
      AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE = "/config/authelia_storage_encryption_key_file";
      #      AUTHELIA_SESSION_REDIS_PASSWORD_FILE =
      #       "/config/authelia_session_redis_password_file";
    };
  };
}

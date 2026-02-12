{
  programs.keychain = {
    enable = true;
    enableZshIntegration = true;
    extraFlags = [ "--systemd" ];
    keys = [ "id_ed25519" "clan-gitea" ];
  };
}

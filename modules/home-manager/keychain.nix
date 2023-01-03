{
  programs.keychain = {
    enable = true;
    enableZshIntegration = true;
    keys = ["id_ed25519"];
    agents = ["gpg" "ssh"];
  };
}

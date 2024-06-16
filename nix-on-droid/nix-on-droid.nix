{
  config,
  lib,
  pkgs,
  ...
}: {
  environment.packages = with pkgs; [
    vim # or some other editor, e.g. nano or neovim

    (pkgs.writeShellScriptBin "sshd-start" ''
      #!${pkgs.runtimeShell}
      echo "Starting sshd in non-daemonized way on port 8022"
      ${pkgs.openssh}/bin/sshd -f "./sshd/sshd_config" -D '')
    openssh
  ];

  # Backup etc files instead of failing to activate generation if a file already exists in /etc
  environment.etcBackupExtension = ".bak";

  # Read the changelog before changing this value
  system.stateVersion = "22.11";

  # Set up nix for flakes
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Set your time zone
  time.timeZone = "America/New_York";
}

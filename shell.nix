# shell.nix
with import <nixpkgs> { };
let
  sops-nix = builtins.fetchTarball {
    url = "https://github.com/Mic92/sops-nix/archive/master.tar.gz";
  };
in mkShell {
  # imports all files ending in .asc/.gpg
  sopsPGPKeys = [ "./secrets/keys/collin.asc" ];
  # Also single files can be imported.
  #sopsPGPKeys = [ 
  #  "./keys/users/mic92.asc"
  #  "./keys/hosts/server01.asc"
  #];

  # This hook can also import gpg keys into its own seperate
  # gpg keyring instead of using the default one. This allows
  # to isolate otherwise unrelated server keys from the user gpg keychain.
  # By uncommenting the following lines, it will set GNUPGHOME
  # to .git/gnupg. 
  # Storing it inside .git prevents accedentially commiting private keys.
  # After setting this option you will also need to import your own
  # private key into keyring, i.e. using a a command like this 
  # (replacing 0000000000000000000000000000000000000000 with your fingerprint)
  # $ (unset GNUPGHOME; gpg --armor --export-secret-key 0000000000000000000000000000000000000000) | gpg --import
  #sopsCreateGPGHome = true;
  # To use a different directory for gpg dirs set sopsGPGHome
  #sopsGPGHome = "${toString ./.}/../gnupg";

  nativeBuildInputs = [ (pkgs.callPackage sops-nix { }).sops-import-keys-hook ];
}

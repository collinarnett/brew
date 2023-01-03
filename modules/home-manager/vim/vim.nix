{pkgs, ...}: let
  vim-nickel = pkgs.vimUtils.buildVimPlugin {
    name = "vim-better-whitespace";
    src = pkgs.fetchFromGitHub {
      owner = "nickel-lang";
      repo = "vim-nickel";
      rev = "90d68675d46e029517a41b0610d8a79dd5a73918";
      sha256 = "sha256-rwpPNZiCnjQK+26NDlkE7R+L33EpZuMlNhGrRNsDK7I";
    };
  };
in {
  programs.vim = {
    enable = true;
    extraConfig = builtins.readFile ./vimrc;
    settings = {number = true;};
    plugins = with pkgs.vimPlugins; [
      ale
      dracula-vim
      markdown-preview-nvim
      nerdtree
      vim-airline
      vim-nix
      vimwiki
      vim-nickel
      jedi-vim
    ];
  };
}

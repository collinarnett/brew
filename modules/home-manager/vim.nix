{ pkgs, ... }:

{
  programs.vim = {
    enable = true;
    extraConfig = ''
      syntax on
      set clipboard=unnamedplus
      set nowrap
      let g:airline_theme='dracula'
      let g:ale_completion_enabled = 1
      let g:ale_lint_on_text_changed = 1
      let g:ale_fix_on_save = 1
      let g:ale_fixers = {
      \ 'nix': [ 'nixfmt' ]
      \}
      let g:ale_linters = {
      \ 'nix': [ 'statix' ]
      \}
      let g:airline#extensions#ale#enabled = 1
      autocmd FileType css setlocal tabstop=2 shiftwidth=2
      autocmd FileType xml setlocal tabstop=2 shiftwidth=2
    '';
    settings = { number = true; };
    plugins = with pkgs.vimPlugins; [ ale vim-nix vim-airline dracula-vim ];
  };
}

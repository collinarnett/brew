{ pkgs, ... }:

{
  programs.vim = {
    enable = true;
    extraConfig = ''
      syntax on
      set clipboard=unnamedplus
      set nowrap
      set omnifunc=ale#completion#OmniFunc
      set t_Co=256
      let g:airline_theme='dracula'
      let g:ale_completion_enabled = 1
      let g:ale_lint_on_text_changed = 1
      let g:ale_fix_on_save = 1
      let g:ale_completion_autoimport = 1
      let g:ale_fixers = {
      \ 'nix': [ 'nixfmt' ],
      \ 'markdown': [ 'pandoc' ]
      \}
      let g:ale_linters = {
      \ 'nix': [ 'statix' ]
      \}
      let g:airline#extensions#ale#enabled = 1
      let g:mkdp_browser = 'firefox'
      highlight link CocErrorSign DraculaErrorLine
      highlight link CocInfoSign DraculaInfoLine
      autocmd FileType css setlocal tabstop=2 shiftwidth=2
      autocmd FileType markdown setlocal tabstop=2 shiftwidth=2
      autocmd FileType json setlocal tabstop=2 shiftwidth=2
      autocmd FileType xml setlocal tabstop=2 shiftwidth=2
      autocmd FileType markdown setlocal spell
      autocmd FileType gitcommit setlocal spell
      nnoremap <leader>n :NERDTreeFocus<CR>
      nnoremap <C-n> :NERDTree<CR>
      nnoremap <C-t> :NERDTreeToggle<CR>
      nnoremap <C-f> :NERDTreeFind<CR>    
    '';
    settings = { number = true; };
    plugins = with pkgs.vimPlugins; [
      ale
      coc-metals
      coc-nvim
      dracula-vim
      markdown-preview-nvim
      nerdtree
      vim-airline
      vim-nix
      vimwiki
    ];
  };
}

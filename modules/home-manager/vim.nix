{ pkgs, ... }:

let 
  vim-nickel = pkgs.vimUtils.buildVimPlugin {
    name = "vim-better-whitespace";
    src = pkgs.fetchFromGitHub {
      owner = "nickel-lang";
      repo = "vim-nickel";
      rev = "90d68675d46e029517a41b0610d8a79dd5a73918";
      sha256 = "sha256-rwpPNZiCnjQK+26NDlkE7R+L33EpZuMlNhGrRNsDK7I";
    };
  };
in 
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
      \ '*': [ 'remove_trailing_lines', 'trim_whitespace' ],
      \ 'nix': [ 'nixfmt' ],
      \ 'markdown': [ 'pandoc' ],
      \ 'scala': [ 'scalafmt' ],
      \ 'haskell': [ 'ormolu' ],
      \ 'python': [ 'black' ],
      \}
      let g:ale_linters = {
      \ 'nix': [ 'statix' ]
      \}
      let g:airline#extensions#ale#enabled = 1
      let g:mkdp_browser = 'firefox'
      highlight link CocErrorSign DraculaErrorLine
      highlight link CocInfoSign DraculaInfoLine
      autocmd FileType css setlocal tabstop=2 shiftwidth=2
      autocmd FileType haskell setlocal tabstop=2 shiftwidth=2
      autocmd FileType json setlocal tabstop=2 shiftwidth=2
      autocmd FileType markdown setlocal spell
      autocmd FileType markdown setlocal tabstop=2 shiftwidth=2
      autocmd FileType xml setlocal tabstop=2 shiftwidth=2
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
      vim-nickel
      jedi-vim
    ];
  };
}

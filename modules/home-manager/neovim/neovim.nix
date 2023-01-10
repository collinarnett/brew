{pkgs, ...}: {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    plugins = with pkgs.vimPlugins; [
      neo-tree-nvim # File-browser
      vimwiki # Wiki
      {
        plugin = lualine-nvim;
        type = "lua";
        config = ''
          require('lualine').setup(
            { options = { theme = 'dracula' }}
          )
        '';
      } # Status Line
      {
        plugin = nvim-treesitter.withAllGrammars; # Syntax Highlighting
        type = "lua";
        config = ''
          require('nvim-treesitter.configs').setup {
            highlight = { enable = true}
          }
        '';
      }
      {
        plugin = null-ls-nvim;
        type = "lua";
        config = ''
          local null_ls = require("null-ls")
          local augroup = vim.api.nvim_create_augroup("LspFormatting", {})
          null_ls.setup({
              sources = {
                  null_ls.builtins.formatting.alejandra.with({
                      command = "${pkgs.alejandra}/bin/alejandra"
                  }), null_ls.builtins.formatting.lua_format.with({
                      command = "${pkgs.luaformatter}/bin/lua-format"
                  })
              },

              on_attach = function(client, bufnr)
                  if client.supports_method("textDocument/formatting") then
                      vim.api.nvim_clear_autocmds({group = augroup, buffer = bufnr})
                      vim.api.nvim_create_autocmd("BufWritePre", {
                          group = augroup,
                          buffer = bufnr,
                          callback = function()
                              vim.lsp.buf.format({
                                  bufnr = bufnr,
                                  filter = function(client)
                                      return client.name == "null-ls"
                                  end
                              })
                          end
                      })
                  end
              end
          })
        '';
      }
      {
        plugin = nvim-lspconfig;
        type = "lua";
        config = ''
          require('lspconfig').nil_ls.setup({
            cmd = { "${pkgs.nil}/bin/nil" }
          })
        '';
      }
      markdown-preview-nvim # Markdown Preview
      dracula-nvim # Theme
      nvim-metals # Scala
    ];
    extraConfig = ''
      :set number
      :set expandtab
      autocmd FileType css setlocal tabstop=2 shiftwidth=2
      autocmd FileType haskell setlocal tabstop=2 shiftwidth=2
      autocmd FileType nix setlocal tabstop=2 shiftwidth=2
      autocmd FileType json setlocal tabstop=2 shiftwidth=2
      autocmd FileType cpp setlocal tabstop=2 shiftwidth=2
      autocmd FileType c setlocal tabstop=2 shiftwidth=2
      autocmd FileType java setlocal tabstop=4 shiftwidth=4
      autocmd FileType markdown setlocal spell
      autocmd FileType markdown setlocal tabstop=2 shiftwidth=2
      au BufRead,BufNewFile *.wiki setlocal textwidth=80 spell tabstop=2 shiftwidth=2
      autocmd FileType xml setlocal tabstop=2 shiftwidth=2
      autocmd FileType help wincmd L
      autocmd FileType gitcommit setlocal spell
    '';
  };
}

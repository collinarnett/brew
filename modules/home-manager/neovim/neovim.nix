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
          local function metals_status()
            return vim.g["metals_status"] or ""
          end
          require('lualine').setup(
            {
              options = { theme = 'dracula-nvim' },
              sections = {
                lualine_a = { 'mode' },
                lualine_b = { 'branch', 'diff' },
                lualine_c = { 'filename', metals_status },
                lualine_x = {'encoding', 'filetype'},
                lualine_y = {'progress'},
                lualine_z = {'location'}
              }
            }
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
      {
        plugin = bufferline-nvim;
        type = "lua";
        config = ''
          require("bufferline").setup{}
        '';
      }
      {
        plugin = nvim-web-devicons;
        type = "lua";
        config = ''
          require("nvim-web-devicons").setup{}
        '';
      }
      {
        plugin = telescope-nvim;
        type = "lua";
        config = ''
          local builtin = require('telescope.builtin')
          vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
          vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
          vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
          vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
          require("telescope").setup{}
        '';
      }
      plenary-nvim
      markdown-preview-nvim # Markdown Preview
      {
        plugin = dracula-nvim;
        type = "lua";
        config = ''
          require("dracula").setup{}
          vim.cmd[[colorscheme dracula]]
        '';
      }
      {
        plugin = nvim-metals;
        type = "lua";
        config = ''
          metals_config = require("metals").bare_config()
          metals_config.settings = {
            useGlobalExecutable = true
          }
          metals_config.init_options.statusBarProvider = "on"
          local nvim_metals_group = vim.api.nvim_create_augroup("nvim-metals", { clear = true })
          vim.api.nvim_create_autocmd("FileType", {
            pattern = { "scala", "sbt", "java" },
            callback = function()
              require("metals").initialize_or_attach(metals_config)
            end,
            group = nvim_metals_group,
          })
        '';
      }
    ];
    extraConfig = ''
      map <Space> <Leader>
      :set number
      :set expandtab
      if has("autocmd")
        au BufReadPost * if line("'\"") > 0 && line("'\"") <= line("$") | exe "normal! g`\"" | endif
      endif
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
    extraPackages = with pkgs; [
      ripgrep # Requirement for telescope
    ];
  };
}

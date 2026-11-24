return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}

      vim.list_extend(opts.ensure_installed, {
        "c",
        "cpp",
        "java",
        "python",
        "bash",
        "lua",
        "css",
        "html",
        "javascript",
        "typescript",
        "json",
        "jsonc",
        "yaml",
        "toml",
        "markdown",
        "markdown_inline",
        "vim",
        "vimdoc",
        "regex",
        "hyprlang",
      })

      -- Highlight: disable for hyprlang + large files
      opts.highlight = opts.highlight or {}
      opts.highlight.enable = true
      opts.highlight.disable = function(lang, buf)
        if lang == "hyprlang" then
          return true
        end
        local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
        if ok and stats and stats.size > 200 * 1024 then
          return true
        end
      end

      -- ✅ THIS is what fixes the ghost text gaps
      opts.indent = opts.indent or {}
      opts.indent.enable = true
      opts.indent.disable = { "hyprlang" }

      -- Incremental selection
      opts.incremental_selection = opts.incremental_selection or {}
      opts.incremental_selection.enable = true
      opts.incremental_selection.keymaps = {
        init_selection = "<C-space>",
        node_incremental = "<C-space>",
        scope_incremental = "<C-s>",
        node_decremental = "<M-space>",
      }
    end,
  },
}

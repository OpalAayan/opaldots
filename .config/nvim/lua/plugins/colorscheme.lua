return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      styles = { comments = { "italic" } },
      integrations = {
        gitsigns = true,
        mason = true,
        noice = true,
        snacks = true,
        telescope = true,
        which_key = true,
        mini = true,
      },
    },
  },
  { "rose-pine/neovim", name = "rose-pine" },
  { "folke/tokyonight.nvim" },
  { "rebelot/kanagawa.nvim" },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin-mocha",
    },
  },
}
